#!/bin/bash
echo "========================= begin $0 ================="

# 环境变量默认值
: ${WORK_DIR:=/tmp/openwrt_build}
: ${OUTPUT_DIR:=/opt/openwrt_packit/output}
: ${KERNEL_PKG_HOME:=/opt/kernel}
: ${OPENWRT_VER:=unknown}

# 全局设置
set -e
mkdir -p "$WORK_DIR" "$OUTPUT_DIR"

# ------------------------- 自动检测内核版本 -------------------------
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

# ------------------------- 辅助函数 -------------------------
check_file() {
    if [ ! -f "$1" ]; then
        echo "ERROR: Missing required file: $1"
        exit 1
    fi
}

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

# 双分区：p1 = FAT32 (256MB), p2 = ext4 (剩余空间)
create_partition() {
    local dev="$1"
    echo "Partitioning $dev with MBR (two partitions: FAT32 + ext4)..."
    parted -s "$dev" mklabel msdos
    parted -s "$dev" mkpart primary fat32 1MiB 256MiB
    parted -s "$dev" mkpart primary ext4 256MiB 100%
    parted -s "$dev" set 1 boot on
    partprobe "$dev" 2>/dev/null
    sleep 2
}

make_filesystem() {
    local dev="$1" part="$2" type="$3" label="$4"
    local part_dev="${dev}p${part}"
    if [ "$type" = "ext4" ]; then
        echo "Formatting $part_dev as ext4 (label $label)..."
        mkfs.ext4 -F -L "$label" "$part_dev" >/dev/null
    elif [ "$type" = "fat32" ]; then
        echo "Formatting $part_dev as FAT32 (label $label)..."
        mkfs.vfat -F 32 -n "$label" "$part_dev" >/dev/null
    else
        echo "Unknown filesystem type: $type"
        exit 1
    fi
}

mount_fs() {
    local dev="$1" dir="$2" type="$3" opts="$4"
    mkdir -p "$dir"
    mount -t "$type" -o "$opts" "$dev" "$dir" || { echo "Mount failed"; exit 1; }
}

# 提取根文件系统到 p2
extract_rootfs() {
    echo "Extracting rootfs to $TGT_ROOT ..."
    tar -xzf "$OPWRT_ROOTFS_GZ" -C "$TGT_ROOT"
    if [ -d "$TGT_ROOT/etc_org" ]; then
        rm -rf "$TGT_ROOT/etc"
        mv "$TGT_ROOT/etc_org" "$TGT_ROOT/etc"
    fi
}

# 提取内核、DTB 并放置到 p1 (FAT32)
extract_boot_to_p1() {
    echo "Extracting boot files (kernel, dtb) to $TGT_BOOT ..."
    tar -xzf "$BOOT_TGZ" -C "$TGT_BOOT"
    # DTB 放入 dtb/rockchip 子目录
    mkdir -p "$TGT_BOOT/dtb/rockchip"
    tar -xzf "$DTBS_TGZ" -C "$TGT_BOOT/dtb/rockchip"
    # 兼容 LTS dtb 名称
    if [ -f "$TGT_BOOT/dtb/rockchip/rk3568-nanopi-r5s-lts.dtb" ] && [ ! -f "$TGT_BOOT/dtb/rockchip/rk3568-nanopi-r5s.dtb" ]; then
        ln -sf rk3568-nanopi-r5s-lts.dtb "$TGT_BOOT/dtb/rockchip/rk3568-nanopi-r5s.dtb"
    fi
}

# 创建 extlinux.conf
create_extlinux_conf() {
    local boot_dir="$1"
    local root_uuid="$2"
    mkdir -p "$boot_dir/extlinux"
    cat > "$boot_dir/extlinux/extlinux.conf" <<EOF
TIMEOUT 30
DEFAULT primary

LABEL primary
    LINUX /Image
    FDT /dtb/rockchip/rk3568-nanopi-r5s.dtb
    APPEND root=UUID=${root_uuid} rootfstype=ext4 console=tty0 console=ttyS2,1500000n8 consoleblank=0 loglevel=7
EOF
    sync
}

# 写入 U-Boot
write_uboot() {
    local dev="$1"
    echo "Writing U-Boot to $dev ..."
    dd if="$UBOOT_IDBLOADER" of="$dev" bs=512 seek=64 conv=notrunc,fsync status=progress
    dd if="$UBOOT_ITB" of="$dev" bs=512 seek=16384 conv=notrunc,fsync status=progress
    sync
}

# 占位函数（可根据需要扩展）
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
    local root_uuid="$1"
    cat > "$TGT_ROOT/etc/fstab" <<EOF
UUID=${root_uuid} / ext4 rw,relatime 0 1
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

create_snapshot() { :; }

# 复制补充文件
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

# ------------------------- 主流程 -------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 检查必要的输入文件
MODULES_TGZ="${KERNEL_PKG_HOME}/modules-${KERNEL_VERSION}.tar.gz"
BOOT_TGZ="${KERNEL_PKG_HOME}/boot-${KERNEL_VERSION}.tar.gz"
DTBS_TGZ="${KERNEL_PKG_HOME}/dtb-rockchip-${KERNEL_VERSION}.tar.gz"
check_file "$MODULES_TGZ"
check_file "$BOOT_TGZ"
check_file "$DTBS_TGZ"

OPWRT_ROOTFS_GZ=$(get_openwrt_rootfs_archive "$PWD")
check_file "$OPWRT_ROOTFS_GZ"
echo "Using rootfs: $OPWRT_ROOTFS_GZ"

UBOOT_IDBLOADER="/tmp/uboot/idbloader.img"
UBOOT_ITB="/tmp/uboot/u-boot.itb"
check_file "$UBOOT_IDBLOADER"
check_file "$UBOOT_ITB"

# 镜像大小 (单位 MB)
SIZE=2560
TGT_IMG="${WORK_DIR}/openwrt_${SOC}_${BOARD}_${OPENWRT_VER}_k${KERNEL_VERSION}${SUBVER}.img"

create_image "$TGT_IMG" "$SIZE"
TGT_DEV=$(losetup -f --show "$TGT_IMG")
if [ -z "$TGT_DEV" ]; then
    echo "ERROR: Failed to setup loop device"
    exit 1
fi
echo "Loop device: $TGT_DEV"

create_partition "$TGT_DEV"
make_filesystem "$TGT_DEV" 1 fat32 "BOOT"
make_filesystem "$TGT_DEV" 2 ext4 "ROOTFS"

# 获取根分区 UUID
sleep 2
ROOTFS_UUID=$(blkid -s UUID -o value "${TGT_DEV}p2")
if [ -z "$ROOTFS_UUID" ]; then
    echo "ERROR: Failed to get UUID of root partition"
    exit 1
fi
export ROOTFS_UUID

# 挂载分区
TGT_ROOT="${WORK_DIR}/root"
TGT_BOOT="${WORK_DIR}/boot"
mkdir -p "$TGT_ROOT" "$TGT_BOOT"
mount_fs "${TGT_DEV}p2" "$TGT_ROOT" "ext4" "defaults"
mount_fs "${TGT_DEV}p1" "$TGT_BOOT" "vfat" "defaults"

# 提取根文件系统和启动文件
extract_rootfs
extract_boot_to_p1
create_extlinux_conf "$TGT_BOOT" "$ROOTFS_UUID"

# 将 boot 分区 bind mount 到根文件系统的 /boot
cd "$TGT_ROOT"
mkdir -p boot
mount --bind "$TGT_BOOT" boot

# 执行补充操作
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
create_fstab_config "$ROOTFS_UUID"
adjust_turboacc_config
adjust_ntfs_config
adjust_mosdns_config
patch_admin_status_index_html
adjust_kernel_env
copy_uboot_to_fs
write_release_info
write_banner
config_first_run

# 清理：退出挂载点目录并卸载
cd /
sync

# 卸载 bind mount
umount "$TGT_ROOT/boot" 2>/dev/null || umount -l "$TGT_ROOT/boot"
# 卸载根分区和 boot 分区
umount "$TGT_ROOT" 2>/dev/null || umount -l "$TGT_ROOT"
umount "$TGT_BOOT" 2>/dev/null || umount -l "$TGT_BOOT"

# 写入 U-Boot（需要重新关联 loop 设备）
losetup -d "$TGT_DEV" 2>/dev/null || true
TGT_DEV=$(losetup -f --show "$TGT_IMG")
if [ -z "$TGT_DEV" ]; then
    echo "ERROR: Failed to setup loop device for U-Boot writing"
    exit 1
fi
write_uboot "$TGT_DEV"
losetup -d "$TGT_DEV"

# 压缩最终镜像
mkdir -p "$OUTPUT_DIR"
if [ -f "$TGT_IMG" ]; then
    echo "Compressing image..."
    gzip -c "$TGT_IMG" > "${OUTPUT_DIR}/$(basename "$TGT_IMG").gz"
    if [ $? -eq 0 ]; then
        echo "Image generated: ${OUTPUT_DIR}/$(basename "$TGT_IMG").gz"
        rm -f "$TGT_IMG"   # 删除未压缩的原始文件以节省空间
    else
        echo "ERROR: gzip compression failed"
        exit 1
    fi
else
    echo "ERROR: Image file $TGT_IMG not found!"
    exit 1
fi

echo "========================== end $0 ================================"