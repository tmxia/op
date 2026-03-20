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

# 自动获取 R5S U-Boot 文件（从官方 FriendlyWrt 镜像提取）
get_uboot_files() {
    local uboot_dir="${PWD}/files/rk3568/uboot"
    mkdir -p "$uboot_dir"

    if [ -f "$uboot_dir/idbloader.img" ] && [ -f "$uboot_dir/u-boot.itb" ]; then
        echo "U-Boot files already exist, skipping download."
        return 0
    fi

    # FriendlyWrt 镜像下载地址（请确认最新版本，若失效请自行替换）
    local FW_URL="https://github.com/friendlyarm/Actions-FriendlyWrt/releases/download/FriendlyWrt-2026-03-06/R5S-R5C-Series-FriendlyWrt-24.10-docker.img.gz"
    local temp_img="/tmp/friendlywrt-r5s.img"

    echo "Downloading FriendlyWrt image to extract U-Boot..."
    if ! wget -qO- "$FW_URL" | gunzip > "$temp_img"; then
        echo "Failed to download/extract FriendlyWrt image."
        echo "Please manually place idbloader.img and u-boot.itb in ${uboot_dir}"
        return 1
    fi

    # 提取 idbloader.img (偏移 64 扇区, 长度 16384 扇区)
    dd if="$temp_img" of="$uboot_dir/idbloader.img" bs=512 skip=64 count=16384 status=none
    # 提取 u-boot.itb (偏移 16384 扇区, 长度 8192 扇区)
    dd if="$temp_img" of="$uboot_dir/u-boot.itb" bs=512 skip=16384 count=8192 status=none

    rm -f "$temp_img"
    echo "U-Boot files extracted successfully."
}

# 调用 U-Boot 获取函数（若失败则退出）
get_uboot_files || exit 1

# 自定义路径（所有文件应放在 files/ 下）
BOOTFILES_HOME="${PWD}/files/bootfiles/rockchip/rk3568/nanopi-r5s"
# 确保该目录存在
mkdir -p ${BOOTFILES_HOME}

# 检查 boot 文件是否存在
if [ ! -f "${BOOTFILES_HOME}/Image" ] && [ ! -f "${BOOTFILES_HOME}/zImage" ]; then
    echo "ERROR: No kernel image (Image/zImage) found in ${BOOTFILES_HOME}"
    exit 1
fi
if [ -z "$(ls ${BOOTFILES_HOME}/*.dtb 2>/dev/null)" ]; then
    echo "ERROR: No DTB file found in ${BOOTFILES_HOME}"
    exit 1
fi

# 分区大小（单位 MB）
SKIP_MB=16          # 前16MiB保留给 idbloader + u-boot
BOOT_MB=512         # boot 分区大小
ROOTFS_MB=2048      # 根文件系统大小（可根据需要调整）
SIZE=$((SKIP_MB + BOOT_MB + ROOTFS_MB + 1))

create_image "$TGT_IMG" "$SIZE"
create_partition "$TGT_DEV" "gpt" "$SKIP_MB" "$BOOT_MB" "ext4" "0" "-1" "btrfs"
make_filesystem "$TGT_DEV" "B" "ext4" "BOOT" "R" "btrfs" "ROOTFS"
mount_fs "${TGT_DEV}p1" "${TGT_BOOT}" "ext4"
mount_fs "${TGT_DEV}p2" "${TGT_ROOT}" "btrfs" "compress=zstd:${ZSTD_LEVEL}"

echo "创建 /etc 子卷 ..."
btrfs subvolume create $TGT_ROOT/etc

extract_rootfs_files

# 将 boot 文件复制到 boot 分区
echo "复制启动文件到 boot 分区 ..."
cp ${BOOTFILES_HOME}/* ${TGT_BOOT}/
# 如果 boot 分区需要 dtb 子目录
mkdir -p ${TGT_BOOT}/dtb/rockchip
cp ${BOOTFILES_HOME}/*.dtb ${TGT_BOOT}/dtb/rockchip/ 2>/dev/null || true

echo "写入 U-Boot 到磁盘 ..."
dd if=${PWD}/files/rk3568/uboot/idbloader.img of=${TGT_DEV} bs=512 seek=64 conv=fsync 2>/dev/null
dd if=${PWD}/files/rk3568/uboot/u-boot.itb of=${TGT_DEV} bs=512 seek=16384 conv=fsync 2>/dev/null

echo "修改引导分区相关配置 ... "
cd $TGT_BOOT

# 检测内核文件名（可能是 Image 或 zImage）
if [ -f "Image" ]; then
    KERNEL_FILE="Image"
elif [ -f "zImage" ]; then
    KERNEL_FILE="zImage"
else
    echo "Error: No kernel file found in boot partition!"
    exit 1
fi

# 检测 DTB 文件（可能带变体后缀）
DTB_FILE=$(basename $(ls dtb/rockchip/rk3568-nanopi-r5s*.dtb 2>/dev/null | head -n1))
if [ -z "$DTB_FILE" ]; then
    echo "Error: No matching DTB file found for Nanopi R5S!"
    exit 1
fi

mkdir -p extlinux
cat > extlinux/extlinux.conf <<EOF
LABEL OpenWrt
    KERNEL ../${KERNEL_FILE}
    FDT ../dtb/rockchip/${DTB_FILE}
    APPEND root=/dev/mmcblk0p2 rootfstype=btrfs rootflags=compress=zstd:${ZSTD_LEVEL} console=ttyS2,1500000n8 console=tty0 earlycon=uart8250,mmio32,0xfe660000 init=/sbin/init rw
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

# 注意：已手动写入 U-Boot，不再调用 write_uboot_to_disk
# write_uboot_to_disk

clean_work_env
mv ${TGT_IMG} ${OUTPUT_DIR} && sync
echo "镜像已生成! 存放在 ${OUTPUT_DIR} 下面!"
echo "========================== end $0 ================================"
echo