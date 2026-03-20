#!/bin/bash
echo "========================= begin $0 ================="
source make.env
source public_funcs
init_work_env

# 默认是否开启软件FLOWOFFLOAD
SW_FLOWOFFLOAD=0
HW_FLOWOFFLOAD=0
SFE_FLOW=1

PLATFORM=rockchip
SOC=rk3568
BOARD=nanopi-r5s
SUBVER=$1

# Kernel image sources (不再需要，但保留变量避免报错)
KERNEL_TAGS="stable"
KERNEL_BRANCHES="bsp:rk35xx:>=:5.10 mainline:all:>=:6.1"

# Openwrt rootfs
OPWRT_ROOTFS_GZ=$(get_openwrt_rootfs_archive ${PWD})
check_file ${OPWRT_ROOTFS_GZ}
echo "Use $OPWRT_ROOTFS_GZ as openwrt rootfs!"

# Target Image
TGT_IMG="${WORK_DIR}/openwrt_${SOC}_${BOARD}_${OPENWRT_VER}_k${KERNEL_VERSION}${SUBVER}.img"

# 自动获取 R5S U-Boot 文件（从官方 FriendlyWrt 镜像提取）
get_uboot_files() {
    local uboot_dir="${PWD}/files/rk3568/uboot"
    mkdir -p "$uboot_dir"

    if [ -f "$uboot_dir/idbloader.img" ] && [ -f "$uboot_dir/u-boot.itb" ]; then
        echo "U-Boot files already exist, skipping download."
        return 0
    fi

    local FW_URL="https://github.com/friendlyarm/Actions-FriendlyWrt/releases/download/FriendlyWrt-2026-03-06/R5S-R5C-Series-FriendlyWrt-24.10-docker.img.gz"
    local temp_img="/tmp/friendlywrt-r5s.img"

    echo "Downloading FriendlyWrt image to extract U-Boot..."
    if ! wget -qO- "$FW_URL" | gunzip > "$temp_img"; then
        echo "Failed to download/extract FriendlyWrt image."
        echo "Please manually place idbloader.img and u-boot.itb in ${uboot_dir}"
        return 1
    fi

    dd if="$temp_img" of="$uboot_dir/idbloader.img" bs=512 skip=64 count=16384 status=none
    dd if="$temp_img" of="$uboot_dir/u-boot.itb" bs=512 skip=16384 count=8192 status=none

    rm -f "$temp_img"
    echo "U-Boot files extracted successfully."
}

get_uboot_files || exit 1

# Boot 文件目录（从官方镜像提取）
BOOTFILES_HOME="${PWD}/files/bootfiles/rockchip/rk3568/nanopi-r5s"
if [ ! -d "$BOOTFILES_HOME" ]; then
    echo "ERROR: Boot files directory $BOOTFILES_HOME not found!"
    exit 1
fi
# 检查关键文件是否存在
if [ ! -f "$BOOTFILES_HOME/Image" ] && [ ! -f "$BOOTFILES_HOME/zImage" ]; then
    echo "ERROR: No kernel image found in $BOOTFILES_HOME"
    exit 1
fi
if [ -z "$(ls $BOOTFILES_HOME/*.dtb 2>/dev/null)" ]; then
    echo "ERROR: No DTB file found in $BOOTFILES_HOME"
    exit 1
fi

# 分区大小（单位 MB）
SKIP_MB=16          # 前16MiB保留给 idbloader + u-boot
BOOT_MB=512         # boot 分区大小
ROOTFS_MB=2048      # 根文件系统大小
SIZE=$((SKIP_MB + BOOT_MB + ROOTFS_MB + 1))

create_image "$TGT_IMG" "$SIZE"
create_partition "$TGT_DEV" "gpt" "$SKIP_MB" "$BOOT_MB" "ext4" "0" "-1" "btrfs"
make_filesystem "$TGT_DEV" "B" "ext4" "BOOT" "R" "btrfs" "ROOTFS"
mount_fs "${TGT_DEV}p1" "${TGT_BOOT}" "ext4"
mount_fs "${TGT_DEV}p2" "${TGT_ROOT}" "btrfs" "compress=zstd:${ZSTD_LEVEL}"

echo "创建 /etc 子卷 ..."
btrfs subvolume create $TGT_ROOT/etc

# 提取 rootfs 内容
extract_rootfs_files

# 复制官方 boot 文件到 boot 分区
echo "复制官方启动文件到 boot 分区 ..."
cp -r $BOOTFILES_HOME/* $TGT_BOOT/
# 确保 extlinux 目录存在（官方镜像可能包含）
mkdir -p $TGT_BOOT/extlinux

echo "写入 U-Boot 到磁盘 ..."
dd if=${PWD}/files/rk3568/uboot/idbloader.img of=${TGT_DEV} bs=512 seek=64 conv=fsync 2>/dev/null
dd if=${PWD}/files/rk3568/uboot/u-boot.itb of=${TGT_DEV} bs=512 seek=16384 conv=fsync 2>/dev/null

echo "修改根文件系统相关配置 ... "
cd $TGT_ROOT
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

# 注意：已手动写入 U-Boot，不再调用 write_uboot_to_disk
# write_uboot_to_disk

clean_work_env
mv ${TGT_IMG} ${OUTPUT_DIR} && sync
echo "镜像已生成! 存放在 ${OUTPUT_DIR} 下面!"
echo "========================== end $0 ================================"
echo