#!/bin/bash
# ==============================================================
# 打包脚本：为 FriendlyARM Nanopi R5S 生成 OpenWrt 固件镜像
# 支持内核版本：6.12.y 和 6.6.y
# 依赖：openwrt_packit 环境（make.env, public_funcs 等）
# ==============================================================

echo "========================= begin $0 ================="
source make.env
source public_funcs
init_work_env

# 默认加速开关（可根据需要调整）
SW_FLOWOFFLOAD=0
HW_FLOWOFFLOAD=0
SFE_FLOW=1

PLATFORM=rockchip
SOC=rk3568
BOARD=nanopi-r5s
SUBVER=$1

# Kernel 相关变量（由 openwrt_packit 传入）
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

# Openwrt rootfs 压缩包
OPWRT_ROOTFS_GZ=$(get_openwrt_rootfs_archive ${PWD})
check_file ${OPWRT_ROOTFS_GZ}
echo "Use $OPWRT_ROOTFS_GZ as openwrt rootfs!"

# 目标镜像文件名
TGT_IMG="${WORK_DIR}/openwrt_${SOC}_${BOARD}_${OPENWRT_VER}_k${KERNEL_VERSION}${SUBVER}.img"

# ==================== U-Boot 获取函数（增强版）====================
# 优先使用本地文件，否则从官方镜像下载并提取
get_uboot_files() {
    local uboot_dir="${PWD}/files/rk3568/uboot"
    mkdir -p "$uboot_dir"

    # 1. 如果本地已有文件（手动放入仓库），直接使用
    if [ -f "$uboot_dir/idbloader.img" ] && [ -f "$uboot_dir/u-boot.itb" ]; then
        echo "U-Boot files already exist in repository, skipping download."
        return 0
    fi

    # 2. 定义下载源（用户确认有效的官方链接）
    local FW_URL="https://github.com/friendlyarm/Actions-FriendlyWrt/releases/download/FriendlyWrt-2026-03-06/R5S-R5C-Series-FriendlyWrt-24.10-docker.img.gz"
    local temp_img="/tmp/friendlywrt-r5s.img"
    local max_retries=3
    local retry_count=0
    local success=1

    echo "Downloading FriendlyWrt image from official source to extract U-Boot..."
    while [ $retry_count -lt $max_retries ]; do
        # 使用 wget 的 --timeout 和 --tries 参数，并允许继续部分下载 (-c)
        if wget -q --timeout=60 --tries=3 -c "$FW_URL" -O- | gunzip > "$temp_img" 2>/dev/null; then
            # 检查下载的文件大小是否合理（例如大于 100MB）
            if [ -f "$temp_img" ] && [ $(stat -c%s "$temp_img") -gt 100000000 ]; then
                echo "Download successful (attempt $((retry_count+1)))."
                success=0
                break
            else
                echo "Downloaded file is too small or empty, retrying..."
            fi
        else
            echo "Download attempt $((retry_count+1)) failed, retrying..."
        fi
        retry_count=$((retry_count+1))
        sleep 5
    done

    if [ $success -ne 0 ]; then
        echo "ERROR: Failed to download U-Boot image after $max_retries attempts."
        echo "Please manually place 'idbloader.img' and 'u-boot.itb' in the '${uboot_dir}' directory, or check the network."
        exit 1
    fi

    # 3. 精确提取 U-Boot 组件
    echo "Extracting U-Boot files..."
    # idbloader.img (从 64 扇区开始，取 16KB 足够，但保守取 8MB)
    dd if="$temp_img" of="$uboot_dir/idbloader.img" bs=512 skip=64 count=16384 status=none
    # u-boot.itb (从 16384 扇区开始，取 8MB)
    dd if="$temp_img" of="$uboot_dir/u-boot.itb" bs=512 skip=16384 count=16384 status=none

    # 4. 验证提取的文件非空
    if [ ! -s "$uboot_dir/idbloader.img" ] || [ ! -s "$uboot_dir/u-boot.itb" ]; then
        echo "ERROR: Extracted U-Boot files are empty."
        rm -f "$temp_img"
        exit 1
    fi

    rm -f "$temp_img"
    echo "U-Boot files extracted successfully."
}
# ============================================================

# 调用 U-Boot 获取函数（若失败则退出）
get_uboot_files || exit 1

# 确保 bootfiles 目录存在（用于占位，防止 cp 错误）
mkdir -p ${BOOTFILES_HOME}
touch ${BOOTFILES_HOME}/placeholder.txt

# 分区大小（单位 MB）
SKIP_MB=16          # 前16MiB保留给 idbloader + u-boot
BOOT_MB=512         # boot 分区大小
ROOTFS_MB=2048      # 根文件系统大小（可根据需要调整）
SIZE=$((SKIP_MB + BOOT_MB + ROOTFS_MB + 1))

# 创建空白镜像文件
create_image "$TGT_IMG" "$SIZE"

# 创建分区表（GPT）
create_partition "$TGT_DEV" "gpt" "$SKIP_MB" "$BOOT_MB" "ext4" "0" "-1" "btrfs"

# 格式化分区
make_filesystem "$TGT_DEV" "B" "ext4" "BOOT" "R" "btrfs" "ROOTFS"

# 挂载分区
mount_fs "${TGT_DEV}p1" "${TGT_BOOT}" "ext4"
mount_fs "${TGT_DEV}p2" "${TGT_ROOT}" "btrfs" "compress=zstd:${ZSTD_LEVEL}"

# 获取 rootfs 分区 UUID（用于 extlinux.conf）
ROOTFS_UUID=$(blkid -s UUID -o value ${TGT_DEV}p2)

echo "创建 /etc 子卷 ..."
btrfs subvolume create $TGT_ROOT/etc

# 解压 OpenWrt rootfs 和内核文件
extract_rootfs_files
extract_rockchip_boot_files

# 写入 U-Boot 到磁盘（偏移量必须与分区预留一致）
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

# 固定 DTB 文件名（Nanopi R5S 标准名称，如有变体请修改）
DTB_FILE="rk3568-nanopi-r5s.dtb"
if [ ! -f "dtb/rockchip/$DTB_FILE" ]; then
    echo "Error: DTB file $DTB_FILE not found in boot partition!"
    exit 1
fi

# 创建 extlinux 配置文件
mkdir -p extlinux
cat > extlinux/extlinux.conf <<EOF
LABEL OpenWrt
    KERNEL ../${KERNEL_FILE}
    FDT ../dtb/rockchip/${DTB_FILE}
    APPEND root=UUID=${ROOTFS_UUID} rootfstype=btrfs rootflags=compress=zstd:${ZSTD_LEVEL} console=ttyS2,1500000n8 console=tty0 init=/sbin/init rw
EOF

echo "extlinux.conf -->"
cat extlinux/extlinux.conf
echo "==============================================================================="
echo

echo "修改根文件系统相关配置 ... "
cd $TGT_ROOT

# 复制用户自定义的增补文件（如 network, firewall 等）
copy_supplement_files

# 以下为 openwrt_packit 提供的标准调整函数
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

# 清理临时文件并移动镜像到输出目录
clean_work_env
mv ${TGT_IMG} ${OUTPUT_DIR} && sync
echo "镜像已生成! 存放在 ${OUTPUT_DIR} 下面!"
echo "========================== end $0 ================================"