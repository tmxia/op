#!/bin/bash
echo "========================= begin $0 ================="
source make.env
source public_funcs
init_work_env

# 默认是否开启软件FLOWOFFLOAD
SW_FLOWOFFLOAD=0
# 默认是否开启硬件FLOWOFFLOAD
HW_FLOWOFFLOAD=0
# 默认是否开启SFE
SFE_FLOW=1

PLATFORM=rockchip
SOC=rk3568
BOARD=nanopi-r5s
SUBVER=$1

# Kernel image sources
###################################################################
KERNEL_TAGS="stable"
KERNEL_BRANCHES="bsp:rk35xx:>=:5.10 mainline:all:>=:6.1"
MODULES_TGZ=${KERNEL_PKG_HOME}/modules-${KERNEL_VERSION}.tar.gz
check_file ${MODULES_TGZ}
BOOT_TGZ=${KERNEL_PKG_HOME}/boot-${KERNEL_VERSION}.tar.gz
check_file ${BOOT_TGZ}
DTBS_TGZ=${KERNEL_PKG_HOME}/dtb-rockchip-${KERNEL_VERSION}.tar.gz
check_file ${DTBS_TGZ}
###################################################################

# Openwrt rootfs
OPWRT_ROOTFS_GZ=$(get_openwrt_rootfs_archive ${PWD})
check_file ${OPWRT_ROOTFS_GZ}
echo "Use $OPWRT_ROOTFS_GZ as openwrt rootfs!"

# Target Image
TGT_IMG="${WORK_DIR}/openwrt_${SOC}_${BOARD}_${OPENWRT_VER}_k${KERNEL_VERSION}${SUBVER}.img"

# 获取 U-Boot 文件（使用稳定的官方源）
get_uboot_files() {
    local uboot_dir="${PWD}/files/rk3568/uboot"
    mkdir -p "$uboot_dir"

    # 如果已有文件，跳过下载
    if [ -f "$uboot_dir/idbloader.img" ] && [ -f "$uboot_dir/u-boot.itb" ]; then
        echo "U-Boot files already exist, skipping download."
        return 0
    fi

    # 从 FriendlyWrt 最新稳定版提取（使用固定链接，或动态获取最新 release）
    # 这里使用已知可用的版本（请确认链接有效，若失效请替换）
    local FW_URL="https://github.com/friendlyarm/Actions-FriendlyWrt/releases/download/FriendlyWrt-24.10/R5S-R5C-Series-FriendlyWrt-24.10.img.gz"
    local temp_img="/tmp/friendlywrt-r5s.img"

    echo "Downloading FriendlyWrt image to extract U-Boot..."
    if ! wget -qO- "$FW_URL" | gunzip > "$temp_img"; then
        echo "Failed to download/extract FriendlyWrt image."
        echo "Please manually place idbloader.img and u-boot.itb in ${uboot_dir}"
        return 1
    fi

    # 精确提取：idbloader 只需 16 扇区（8KB），u-boot.itb 8192 扇区（4MB）
    dd if="$temp_img" of="$uboot_dir/idbloader.img" bs=512 skip=64 count=16 status=none
    dd if="$temp_img" of="$uboot_dir/u-boot.itb" bs=512 skip=16384 count=8192 status=none

    rm -f "$temp_img"
    echo "U-Boot files extracted successfully."
}

# 调用 U-Boot 获取函数（若失败则退出）
get_uboot_files || exit 1

# 其他变量（与用户原脚本保持一致）
# ... [此处省略原脚本中定义的各种路径变量，保持不变] ...

check_depends

# 确保 bootfiles 目录存在
mkdir -p ${BOOTFILES_HOME}
touch ${BOOTFILES_HOME}/placeholder.txt

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

# 获取 rootfs UUID（关键修复）
ROOTFS_UUID=$(blkid -s UUID -o value ${TGT_DEV}p2)

echo "创建 /etc 子卷 ..."
btrfs subvolume create $TGT_ROOT/etc

extract_rootfs_files
extract_rockchip_boot_files

echo "写入 U-Boot 到磁盘 ..."
dd if=${PWD}/files/rk3568/uboot/idbloader.img of=${TGT_DEV} bs=512 seek=64 conv=fsync 2>/dev/null
dd if=${PWD}/files/rk3568/uboot/u-boot.itb of=${TGT_DEV} bs=512 seek=16384 conv=fsync 2>/dev/null

echo "修改引导分区相关配置 ... "
cd $TGT_BOOT

# 检测内核文件名
if [ -f "Image" ]; then
    KERNEL_FILE="Image"
elif [ -f "zImage" ]; then
    KERNEL_FILE="zImage"
else
    echo "Error: No kernel file found in boot partition!"
    exit 1
fi

# 固定 DTB 文件名（避免通配符歧义）
DTB_FILE="rk3568-nanopi-r5s.dtb"
if [ ! -f "dtb/rockchip/$DTB_FILE" ]; then
    echo "Error: DTB file $DTB_FILE not found in boot partition!"
    exit 1
fi

mkdir -p extlinux
cat > extlinux/extlinux.conf <<EOF
LABEL OpenWrt
    KERNEL ../${KERNEL_FILE}
    FDT ../dtb/rockchip/${DTB_FILE}
    APPEND root=UUID=${ROOTFS_UUID} rootfstype=btrfs rootflags=compress=zstd:${ZSTD_LEVEL} console=ttyS2,1500000n8 console=tty0 init=/sbin/init rw
EOF

echo "extlinux.conf -->"
echo "==============================================================================="
cat extlinux/extlinux.conf
echo "==============================================================================="
echo

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

clean_work_env
mv ${TGT_IMG} ${OUTPUT_DIR} && sync
echo "镜像已生成! 存放在 ${OUTPUT_DIR} 下面!"
echo "========================== end $0 ================================"