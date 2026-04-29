#!/bin/bash
echo "========================= begin $0 ================="

# ----------------------------------------------------------------------
# 环境变量及默认值（由 openwrt_packit 提供）
# WORK_DIR, OUTPUT_DIR, KERNEL_PKG_HOME, KERNEL_VERSION, OPENWRT_VER
# ----------------------------------------------------------------------
: ${WORK_DIR:=/tmp/openwrt_build}
: ${OUTPUT_DIR:=/opt/openwrt_packit/output}
: ${KERNEL_PKG_HOME:=/opt/kernel}
: ${KERNEL_VERSION:=unknown}
: ${OPENWRT_VER:=unknown}
: ${ZSTD_LEVEL:=3}

# 平台设置
PLATFORM=rockchip
SOC=rk3568
BOARD=nanopi-r5s
SUBVER=$1

# 流控开关
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

# 获取 rootfs 归档路径（openwrt_packit 会通过 OPENWRT_ARMVIRT 传入）
get_openwrt_rootfs_archive() {
    local workdir="$1"
    # 优先使用 OPENWRT_ARMVIRT 环境变量（由 packit 设置）
    if [ -n "$OPENWRT_ARMVIRT" ] && [ -f "$OPENWRT_ARMVIRT" ]; then
        echo "$OPENWRT_ARMVIRT"
        return
    fi
    # 否则查找当前目录下的 rootfs.tar.gz
    if [ -f "$workdir/rootfs.tar.gz" ]; then
        echo "$workdir/rootfs.tar.gz"
        return
    fi
    echo "ERROR: Cannot find rootfs archive"
    exit 1
}

# 创建空白镜像文件
create_image() {
    local img="$1" size="$2"
    echo "Creating blank image of ${size}M ..."
    dd if=/dev/zero of="$img" bs=1M count="$size" status=none
}

# 分区 (GPT)
create_partition() {
    local dev="$1" label="$2" skip_mb="$3" boot_mb="$4" boot_fs="$5" ...
    echo "Partitioning $dev with GPT ..."
    parted -s "$dev" mklabel gpt
    parted -s "$dev" mkpart primary "$boot_fs" ${skip_mb}M $((skip_mb + boot_mb))M
    parted -s "$dev" mkpart primary btrfs $((skip_mb + boot_mb))M 100%
    parted -s "$dev" set 1 boot on
    partprobe "$dev" 2>/dev/null
    sleep 2
}

# 格式化文件系统
make_filesystem() {
    local dev="$1" part="$2" type="$3" label="$4"
    local part_dev="${dev}p${part}"
    echo "Formatting $part_dev as $type (label $label)..."
    if [ "$type" = "ext4" ]; then
        mkfs.ext4 -F -L "$label" "$part_dev" >/dev/null
    elif [ "$type" = "btrfs" ]; then
        mkfs.btrfs -f -L "$label" "$part_dev" >/dev/null
    else
        mkfs."$type" "$part_dev" >/dev/null
    fi
}

# 挂载分区
mount_fs() {
    local dev="$1" dir="$2" type="$3" opts="$4"
    mkdir -p "$dir"
    mount -t "$type" -o "$opts" "$dev" "$dir" || { echo "Mount failed"; exit 1; }
}

# 提取 rootfs
extract_rootfs_files() {
    echo "Extracting rootfs to $TGT_ROOT ..."
    tar -xzf "$OPWRT_ROOTFS_GZ" -C "$TGT_ROOT"
    # 如果存在 /etc_org，则需要移入子卷（但我们的子卷已创建）
    if [ -d "$TGT_ROOT/etc_org" ]; then
        rm -rf "$TGT_ROOT/etc"
        mv "$TGT_ROOT/etc_org" "$TGT_ROOT/etc"
    fi
}

# 提取 boot 和 dtb 文件
extract_rockchip_boot_files() {
    echo "Extracting boot files from $BOOT_TGZ ..."
    tar -xzf "$BOOT_TGZ" -C "$TGT_BOOT"
    echo "Extracting dtb files from $DTBS_TGZ ..."
    tar -xzf "$DTBS_TGZ" -C "$TGT_BOOT"
}

# 复制补充文件（r5s/files/*）
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

# 以下函数可以是空操作或简单的默认配置（你可以按需实现）
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
create_fstab_config() {
    cat > "$TGT_ROOT/etc/fstab" <<EOF
UUID=${ROOTFS_UUID} / btrfs rw,compress=zstd:${ZSTD_LEVEL},relatime 0 1
EOF
}
adjust_turboacc_config() { :; }
adjust_ntfs_config() { :; }
adjust_mosdns_config() { :; }
patch_admin_status_index_html() { :; }
adjust_kernel_env() { :; }
copy_uboot_to_fs() { :; }
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
    local name="$1"
    btrfs subvolume snapshot -r "$TGT_ROOT/etc" "$TGT_ROOT/etc-$name" 2>/dev/null || true
}

# ----------------------------------------------------------------------
# 主流程
# ----------------------------------------------------------------------

# 确定脚本所在目录（用于查找 files 和 U-Boot）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 1. 内核包路径
MODULES_TGZ="${KERNEL_PKG_HOME}/modules-${KERNEL_VERSION}.tar.gz"
BOOT_TGZ="${KERNEL_PKG_HOME}/boot-${KERNEL_VERSION}.tar.gz"
DTBS_TGZ="${KERNEL_PKG_HOME}/dtb-rockchip-${KERNEL_VERSION}.tar.gz"
check_file "$MODULES_TGZ"
check_file "$BOOT_TGZ"
check_file "$DTBS_TGZ"

# 2. rootfs 位置
OPWRT_ROOTFS_GZ=$(get_openwrt_rootfs_archive "$PWD")
check_file "$OPWRT_ROOTFS_GZ"
echo "Using rootfs: $OPWRT_ROOTFS_GZ"

# 3. 目标镜像文件名
TGT_IMG="${WORK_DIR}/openwrt_${SOC}_${BOARD}_${OPENWRT_VER}_k${KERNEL_VERSION}${SUBVER}.img"

# 4. U-Boot 文件
UBOOT_IDBLOADER="${SCRIPT_DIR}/idbloader.img"
UBOOT_ITB="${SCRIPT_DIR}/u-boot.itb"
check_file "$UBOOT_IDBLOADER"
check_file "$UBOOT_ITB"

# 5. 分区大小（单位 MB）
SKIP_MB=16
BOOT_MB=512
ROOTFS_MB=2048
SIZE=$((SKIP_MB + BOOT_MB + ROOTFS_MB + 1))

create_image "$TGT_IMG" "$SIZE"

# 获取 loop 设备
TGT_DEV=$(losetup -f --show "$TGT_IMG")
if [ -z "$TGT_DEV" ]; then
    echo "ERROR: Failed to setup loop device"
    exit 1
fi
echo "Loop device: $TGT_DEV"

# 分区与格式化
create_partition "$TGT_DEV" "gpt" "$SKIP_MB" "$BOOT_MB" "ext4" "0" "-1" "btrfs"
make_filesystem "$TGT_DEV" "1" "ext4" "EMMC_BOOT"
make_filesystem "$TGT_DEV" "2" "btrfs" "EMMC_ROOTFS1"

TGT_BOOT="${WORK_DIR}/boot"
TGT_ROOT="${WORK_DIR}/root"
mkdir -p "$TGT_BOOT" "$TGT_ROOT"

mount_fs "${TGT_DEV}p1" "$TGT_BOOT" "ext4" "defaults"
mount_fs "${TGT_DEV}p2" "$TGT_ROOT" "btrfs" "compress=zstd:${ZSTD_LEVEL}"
echo "Creating /etc subvolume ..."
btrfs subvolume create "$TGT_ROOT/etc"

# 提取 rootfs 和 boot 文件
extract_rootfs_files
extract_rockchip_boot_files

# 配置 armbianEnv.txt（R5S 专用）
cd "$TGT_BOOT"
sed -i '/rootdev=/d' armbianEnv.txt 2>/dev/null
sed -i '/rootfstype=/d' armbianEnv.txt 2>/dev/null
sed -i '/rootflags=/d' armbianEnv.txt 2>/dev/null
cat >> armbianEnv.txt <<EOF
verbosity=1
bootlogo=false
console=serial
overlay_prefix=rockchip
fdtfile=rockchip/rk3568-nanopi-r5s.dtb
rootdev=UUID=${ROOTFS_UUID}
rootfstype=btrfs
rootflags=compress=zstd:${ZSTD_LEVEL}
extraargs=cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory swapaccount=1
EOF
echo "armbianEnv.txt content:"
cat armbianEnv.txt

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
create_snapshot "etc-000"

# 写入 U-Boot 到磁盘
echo "Writing U-Boot to $TGT_DEV ..."
dd if="$UBOOT_IDBLOADER" of="$TGT_DEV" bs=512 seek=64 conv=notrunc,fsync status=progress
dd if="$UBOOT_ITB" of="$TGT_DEV" bs=512 seek=16384 conv=notrunc,fsync status=progress

# 清理
sync
umount "$TGT_BOOT" "$TGT_ROOT"
losetup -d "$TGT_DEV"

# 移动最终镜像到输出目录
mkdir -p "$OUTPUT_DIR"
mv "$TGT_IMG" "$OUTPUT_DIR/" && sync

echo "Image generated: $OUTPUT_DIR/$(basename "$TGT_IMG")"
echo "========================== end $0 ================================"