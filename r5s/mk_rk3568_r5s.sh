#!/bin/bash
echo "========================= begin $0 ================="

# ----------------------------------------------------------------------
# 环境变量默认值（由 openwrt_packit 提供）
# ----------------------------------------------------------------------
: ${WORK_DIR:=/tmp/openwrt_build}
: ${OUTPUT_DIR:=/opt/openwrt_packit/output}
: ${KERNEL_PKG_HOME:=/opt/kernel}
: ${OPENWRT_VER:=unknown}
: ${ZSTD_LEVEL:=3}   # 虽然改为 ext4，但保留变量，将来可能用于其他压缩

# 确保工作目录存在
mkdir -p "$WORK_DIR" "$OUTPUT_DIR"

# ----------------------------------------------------------------------
# 自动检测内核版本（修复 KERNEL_VERSION 未传递的问题）
# ----------------------------------------------------------------------
if [ -z "$KERNEL_VERSION" ] || [ "$KERNEL_VERSION" = "unknown" ]; then
    MODULES_FILE=$(ls ${KERNEL_PKG_HOME}/modules-*.tar.gz 2>/dev/null | head -n1)
    if [ -n "$MODULES_FILE" ]; then
        KERNEL_VERSION=$(basename "$MODULES_FILE" | sed 's/^modules-//; s/\.tar\.gz$//')
        echo "Auto-detected KERNEL_VERSION: $KERNEL_VERSION"
    else
        echo "ERROR: Cannot detect kernel version from $KERNEL_PKG_HOME"
        exit 1
    fi
fi
export KERNEL_VERSION

PLATFORM=rockchip
SOC=rk3568
BOARD=nanopi-r5s
SUBVER=$1

SW_FLOWOFFLOAD=0
HW_FLOWOFFLOAD=0
SFE_FLOW=1

# ----------------------------------------------------------------------
# 辅助函数
# ----------------------------------------------------------------------
check_file() {
    if [ ! -f "$1" ]; then
        echo "ERROR: Missing required file: $1"
        exit 1
    fi
}

# 获取 rootfs 归档（优先使用 openwrt_packit 固定名称）
get_openwrt_rootfs_archive() {
    local workdir="$1"
    if [ -f "./openwrt-armsr-armv8-generic-rootfs.tar.gz" ]; then
        realpath "./openwrt-armsr-armv8-generic-rootfs.tar.gz"
        return
    fi
    if [ -n "$OPENWRT_ARMVIRT" ] && [ -f "$OPENWRT_ARMVIRT" ]; then
        echo "$OPENWRT_ARMVIRT"
        return
    fi
    if [ -f "$workdir/rootfs.tar.gz" ]; then
        echo "$workdir/rootfs.tar.gz"
        return
    fi
    echo "ERROR: Cannot find rootfs archive"
    exit 1
}

create_image() {
    local img="$1" size="$2"
    echo "Creating blank image of ${size}M ..."
    dd if=/dev/zero of="$img" bs=1M count="$size" status=none
}

# 修改：创建单分区（ext4），从 skip_mb 开始到结束，使用 MBR（或 GPT，但 MBR 更简单）
create_partition() {
    local dev="$1" skip_mb="$2"
    echo "Partitioning $dev with MBR (single ext4 partition after ${skip_mb}MB)..."
    parted -s "$dev" mklabel msdos
    parted -s "$dev" mkpart primary ext4 ${skip_mb}MB 100%
    parted -s "$dev" set 1 boot on
    partprobe "$dev" 2>/dev/null
    sleep 2
}

make_filesystem() {
    local dev="$1" part="$2" type="$3" label="$4"
    local part_dev="${dev}p${part}"
    echo "Formatting $part_dev as $type (label $label)..."
    if [ "$type" = "ext4" ]; then
        mkfs.ext4 -F -L "$label" "$part_dev" >/dev/null
    else
        mkfs."$type" "$part_dev" >/dev/null
    fi
}

mount_fs() {
    local dev="$1" dir="$2" type="$3" opts="$4"
    mkdir -p "$dir"
    mount -t "$type" -o "$opts" "$dev" "$dir" || { echo "Mount failed"; exit 1; }
}

extract_rootfs_files() {
    echo "Extracting rootfs to $TGT_ROOT ..."
    tar -xzf "$OPWRT_ROOTFS_GZ" -C "$TGT_ROOT"
    if [ -d "$TGT_ROOT/etc_org" ]; then
        rm -rf "$TGT_ROOT/etc"
        mv "$TGT_ROOT/etc_org" "$TGT_ROOT/etc"
    fi
}

extract_rockchip_boot_files() {
    echo "Extracting boot files to $TGT_ROOT/boot ..."
    mkdir -p "$TGT_ROOT/boot"
    tar -xzf "$BOOT_TGZ" -C "$TGT_ROOT/boot"
    echo "Extracting dtb files to $TGT_ROOT/boot ..."
    tar -xzf "$DTBS_TGZ" -C "$TGT_ROOT/boot"
}

copy_supplement_files() {
    local src="$SCRIPT_DIR/files"
    if [ -d "$src" ]; then
        echo "Copying supplement files from $src ..."
        cp -rf "$src"/* "$TGT_ROOT/"
        chmod +x "$TGT_ROOT"/usr/bin/* 2>/dev/null || true
        chmod +x "$TGT_ROOT"/etc/init.d/* 2>/dev/null || true
    else
        echo "Notice: No supplement files found in $src"
    fi
}

# 以下函数为占位（可根据需要扩展）
extract_glibc_programs() { :; }
adjust_docker_config() { :; }
adjust_openssl_config() { :; }
adjust_qbittorrent_config() { :; }
adjust_getty_config() { :; }
adjust_samba_config() { :; }
adjust_nfs_config() { :; }
adjust_openssh_config() { :; }
adjust_openclash_config() { :; }
use_xrayplug_replace_v2rayplug() { :; }
adjust_turboacc_config() { :; }
adjust_ntfs_config() { :; }
adjust_mosdns_config() { :; }
patch_admin_status_index_html() { :; }
adjust_kernel_env() { :; }
copy_uboot_to_fs() { :; }

create_fstab_config() {
    # 单分区，根文件系统为 ext4，使用 UUID
    cat > "$TGT_ROOT/etc/fstab" <<EOF
UUID=${ROOTFS_UUID} / ext4 rw,relatime 0 1
EOF
}

write_release_info() {
    cat > "$TGT_ROOT/etc/openwrt_release" <<EOF
DISTRIB_ID="OpenWrt"
DISTRIB_RELEASE="${OPENWRT_VER}"
DISTRIB_TARGET="rockchip/rk3568"
DISTRIB_DESCRIPTION="NanoPi R5S LTS"
EOF
}

write_banner() {
    cat > "$TGT_ROOT/etc/banner" <<EOF
  ______   _____    _____      _____ 
 |  _ \ \ / / _ \  |  _  \    /  ___|
 | |_) \ V / /_\ \ | | | |    \ '--.
 |  _ < \ / | _ | | | | | |    '--. \
 | |_) | |  | | | | | |/ /    /\__/ /
 |____/ \_/  \_| |_/ |___/     \____/ 
 -------------------------------------
 * 固件版本: ${OPENWRT_VER}
 * 内核版本: ${KERNEL_VERSION}
 * 设备型号: NanoPi R5S LTS
EOF
}

config_first_run() {
    if [ -f "$TGT_ROOT/etc/uci-defaults/99-first-run" ]; then
        chmod +x "$TGT_ROOT/etc/uci-defaults/99-first-run"
    fi
}

create_snapshot() {
    # ext4 不支持子卷快照，仅作占位
    : 
}

# ----------------------------------------------------------------------
# 主流程
# ----------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

MODULES_TGZ="${KERNEL_PKG_HOME}/modules-${KERNEL_VERSION}.tar.gz"
BOOT_TGZ="${KERNEL_PKG_HOME}/boot-${KERNEL_VERSION}.tar.gz"
DTBS_TGZ="${KERNEL_PKG_HOME}/dtb-rockchip-${KERNEL_VERSION}.tar.gz"
check_file "$MODULES_TGZ"
check_file "$BOOT_TGZ"
check_file "$DTBS_TGZ"

OPWRT_ROOTFS_GZ=$(get_openwrt_rootfs_archive "$PWD")
check_file "$OPWRT_ROOTFS_GZ"
echo "Using rootfs: $OPWRT_ROOTFS_GZ"

TGT_IMG="${WORK_DIR}/openwrt_${SOC}_${BOARD}_${OPENWRT_VER}_k${KERNEL_VERSION}${SUBVER}.img"

# 从临时目录读取 U-Boot 文件（由 workflow 提前放入）
UBOOT_IDBLOADER="/tmp/uboot/idbloader.img"
UBOOT_ITB="/tmp/uboot/u-boot.itb"
check_file "$UBOOT_IDBLOADER"
check_file "$UBOOT_ITB"

# 前 16MB 保留给 U-Boot，剩余空间全部分配给根分区
SKIP_MB=16
ROOTFS_MB=2048   # 此值仅用于计算最小大小，实际使用剩余全部空间
# 根据根文件系统实际大小 + 额外 20% 确定总大小，这里简单设为 2560MB（可根据需要调整）
SIZE=2560

create_image "$TGT_IMG" "$SIZE"
TGT_DEV=$(losetup -f --show "$TGT_IMG")
if [ -z "$TGT_DEV" ]; then
    echo "ERROR: Failed to setup loop device"
    exit 1
fi
echo "Loop device: $TGT_DEV"

create_partition "$TGT_DEV" "$SKIP_MB"
make_filesystem "$TGT_DEV" "1" "ext4" "ROOTFS"

# 获取 ext4 分区的 UUID（将在格式化后自动生成，也可以手动指定）
# 等待分区设备出现
sleep 1
ROOTFS_UUID=$(blkid -s UUID -o value "${TGT_DEV}p1")
if [ -z "$ROOTFS_UUID" ]; then
    echo "ERROR: Failed to get UUID of root partition"
    exit 1
fi
export ROOTFS_UUID

TGT_ROOT="${WORK_DIR}/root"
mkdir -p "$TGT_ROOT"
mount_fs "${TGT_DEV}p1" "$TGT_ROOT" "ext4" "defaults"

# 提取 rootfs 和 boot 文件到同一个目录
extract_rootfs_files
extract_rockchip_boot_files

# 配置 extlinux.conf（兼容 Armbian 和官方 U-Boot）
mkdir -p "$TGT_ROOT/boot/extlinux"
cat > "$TGT_ROOT/boot/extlinux/extlinux.conf" <<EOF
TIMEOUT 30
DEFAULT primary

LABEL primary
    LINUX /boot/Image
    FDT /boot/dtb/rockchip/rk3568-nanopi-r5s.dtb
    APPEND root=UUID=${ROOTFS_UUID} rootfstype=ext4 console=tty0 console=ttyS2,1500000n8 consoleblank=0 loglevel=7
EOF

# 同时保留 armbianEnv.txt 用于兼容（如果有 U-Boot 读取它）
cat > "$TGT_ROOT/boot/armbianEnv.txt" <<EOF
verbosity=1
bootlogo=false
console=serial
overlay_prefix=rockchip
fdtfile=rockchip/rk3568-nanopi-r5s.dtb
rootdev=UUID=${ROOTFS_UUID}
rootfstype=ext4
extraargs=cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory swapaccount=1
EOF

echo "extlinux.conf and armbianEnv.txt created"

# 配置根文件系统
cd "$TGT_ROOT"
copy_supplement_files
extract_glibc_programs
adjust_docker_config
adjust_openssl_config
adjust_qbittorrent_config
adjust_getty_config
adjust_samba_config
adjust_nfs_config "mmcblk0p4"
adjust_openssh_config
adjust_openclash_config
use_xrayplug_replace_v2rayplug
create_fstab_config
adjust_turboacc_config
adjust_ntfs_config
adjust_mosdns_config
patch_admin_status_index_html
adjust_kernel_env
copy_uboot_to_fs
write_release_info
write_banner
config_first_run

# 写入 U-Boot
echo "Writing U-Boot to $TGT_DEV ..."
dd if="$UBOOT_IDBLOADER" of="$TGT_DEV" bs=512 seek=64 conv=notrunc,fsync status=progress
dd if="$UBOOT_ITB" of="$TGT_DEV" bs=512 seek=16384 conv=notrunc,fsync status=progress

sync
umount "$TGT_ROOT"
losetup -d "$TGT_DEV"

mkdir -p "$OUTPUT_DIR"
mv "$TGT_IMG" "$OUTPUT_DIR/" && sync
echo "Image generated: $OUTPUT_DIR/$(basename "$TGT_IMG")"
echo "========================== end $0 ================================"