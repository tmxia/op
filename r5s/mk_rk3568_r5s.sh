#!/bin/bash
echo "========================= begin $0 ================="

# ----------------------------------------------------------------------
# 环境变量默认值（由 openwrt_packit 提供）
# ----------------------------------------------------------------------
: ${WORK_DIR:=/tmp/openwrt_build}
: ${OUTPUT_DIR:=/opt/openwrt_packit/output}
: ${KERNEL_PKG_HOME:=/opt/kernel}
: ${OPENWRT_VER:=unknown}
: ${ZSTD_LEVEL:=3}

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
    echo "Extracting boot files from $BOOT_TGZ ..."
    tar -xzf "$BOOT_TGZ" -C "$TGT_BOOT"
    echo "Extracting dtb files from $DTBS_TGZ ..."
    tar -xzf "$DTBS_TGZ" -C "$TGT_BOOT"
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

# 以下函数为占位，可根据需要扩展
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
    cat > "$TGT_ROOT/etc/fstab" <<EOF
UUID=${ROOTFS_UUID} / btrfs rw,compress=zstd:${ZSTD_LEVEL},relatime 0 1
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
    local name="$1"
    btrfs subvolume snapshot -r "$TGT_ROOT/etc" "$TGT_ROOT/etc-$name" 2>/dev/null || true
}

# ----------------------------------------------------------------------
# 主流程
# ----------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 内核包
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

# 关键修改：使用 GITHUB_WORKSPACE 环境变量定位 uboot 文件
if [ -z "$GITHUB_WORKSPACE" ]; then
    echo "ERROR: GITHUB_WORKSPACE not set. Please run in GitHub Actions environment."
    exit 1
fi
UBOOT_IDBLOADER="${GITHUB_WORKSPACE}/uboot/idbloader.img"
UBOOT_ITB="${GITHUB_WORKSPACE}/uboot/u-boot.itb"
check_file "$UBOOT_IDBLOADER"
check_file "$UBOOT_ITB"

SKIP_MB=16
BOOT_MB=512
ROOTFS_MB=2048
SIZE=$((SKIP_MB + BOOT_MB + ROOTFS_MB + 1))

create_image "$TGT_IMG" "$SIZE"
TGT_DEV=$(losetup -f --show "$TGT_IMG")
if [ -z "$TGT_DEV" ]; then
    echo "ERROR: Failed to setup loop device"
    exit 1
fi
echo "Loop device: $TGT_DEV"

create_partition "$TGT_DEV" "gpt" "$SKIP_MB" "$BOOT_MB" "ext4" "0" "-1" "btrfs"
make_filesystem "$TGT_DEV" "1" "ext4" "EMMC_BOOT"
make_filesystem "$TGT_DEV" "2" "btrfs" "EMMC_ROOTFS1"

# 生成 rootfs UUID
ROOTFS_UUID=$(uuidgen)
export ROOTFS_UUID

TGT_BOOT="${WORK_DIR}/boot"
TGT_ROOT="${WORK_DIR}/root"
mkdir -p "$TGT_BOOT" "$TGT_ROOT"

mount_fs "${TGT_DEV}p1" "$TGT_BOOT" "ext4" "defaults"
mount_fs "${TGT_DEV}p2" "$TGT_ROOT" "btrfs" "compress=zstd:${ZSTD_LEVEL}"
echo "Creating /etc subvolume ..."
btrfs subvolume create "$TGT_ROOT/etc"

extract_rootfs_files
extract_rockchip_boot_files

# 配置 armbianEnv.txt
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

# 写入 U-Boot
echo "Writing U-Boot to $TGT_DEV ..."
dd if="$UBOOT_IDBLOADER" of="$TGT_DEV" bs=512 seek=64 conv=notrunc,fsync status=progress
dd if="$UBOOT_ITB" of="$TGT_DEV" bs=512 seek=16384 conv=notrunc,fsync status=progress

sync
umount "$TGT_BOOT" "$TGT_ROOT"
losetup -d "$TGT_DEV"

mkdir -p "$OUTPUT_DIR"
mv "$TGT_IMG" "$OUTPUT_DIR/" && sync
echo "Image generated: $OUTPUT_DIR/$(basename "$TGT_IMG")"
echo "========================== end $0 ================================"