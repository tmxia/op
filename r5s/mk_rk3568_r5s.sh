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

# 通用补丁和脚本目录
####################################################################
CPUSTAT_SCRIPT="${PWD}/files/cpustat"
CPUSTAT_SCRIPT_PY="${PWD}/files/cpustat.py"
INDEX_PATCH_HOME="${PWD}/files/index.html.patches"
GETCPU_SCRIPT="${PWD}/files/getcpu"
KMOD="${PWD}/files/kmod"
KMOD_BLACKLIST="${PWD}/files/kmod_blacklist"
FIRSTRUN_SCRIPT="${PWD}/files/first_run.sh"
DAEMON_JSON="${PWD}/files/rk3568/daemon.json"           # 可选
TTYD="${PWD}/files/ttyd"
FLIPPY="${PWD}/files/scripts_deprecated/flippy_cn"
BANNER="${PWD}/files/banner"
FMW_HOME="${PWD}/files/firmware"
SMB4_PATCH="${PWD}/files/smb4.11_enable_smb1.patch"
SYSCTL_CUSTOM_CONF="${PWD}/files/99-custom.conf"
COREMARK="${PWD}/files/coremark.sh"
BAL_ETH_IRQ="${PWD}/files/balethirq.pl"
FIX_CPU_FREQ="${PWD}/files/fixcpufreq.pl"
SYSFIXTIME_PATCH="${PWD}/files/sysfixtime.patch"
SSL_CNF_PATCH="${PWD}/files/openssl_engine.patch"
BAL_CONFIG="${PWD}/files/rk3568/balance_irq"            # 通用balance_irq配置
SS_LIB="${PWD}/files/ss-glibc/lib-glibc.tar.xz"
SS_BIN="${PWD}/files/ss-glibc/armv8.2a_crypto/ss-bin-glibc.tar.xz"
JQ="${PWD}/files/jq"
DOCKERD_PATCH="${PWD}/files/dockerd.patch"
FIRMWARE_TXZ="${PWD}/files/firmware_armbian.tar.xz"
BOOTFILES_HOME="${PWD}/files/bootfiles/rockchip/rk3568/nanopi-r5s"   # 启动辅助文件（可选）
GET_RANDOM_MAC="${PWD}/files/get_random_mac.sh"
DOCKER_README="${PWD}/files/DockerReadme.pdf"
SYSINFO_SCRIPT="${PWD}/files/30-sysinfo.sh"
FORCE_REBOOT="${PWD}/files/rk3568/reboot"
OPENWRT_KERNEL="${PWD}/files/openwrt-kernel"
OPENWRT_BACKUP="${PWD}/files/openwrt-backup"
OPENWRT_UPDATE="${PWD}/files/openwrt-update-rockchip"
P7ZIP="${PWD}/files/7z"
DDBR="${PWD}/files/openwrt-ddbr"
SSH_CIPHERS="aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr,chacha20-poly1305@openssh.com"
SSHD_CIPHERS="aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr"

# R5S 专用 U-Boot 文件路径（请确保文件已放入仓库）
IDBLOADER_IMG="${PWD}/files/rk3568/uboot/idbloader.img"
UBOOT_ITB="${PWD}/files/rk3568/uboot/u-boot.itb"

# 其他可选目录（如有需要可启用）
# BOARD_HOME="${PWD}/files/rk3568/board.d"
# MODULES_HOME="${PWD}/files/rk3568/modules.d"
# WIRELESS_CONFIG="${PWD}/files/rk3568/wireless"
# RGB_HOME="${PWD}/files/rgb"
####################################################################

check_depends

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
extract_rockchip_boot_files

echo "写入 U-Boot 到磁盘 ..."
dd if=${IDBLOADER_IMG} of=${TGT_DEV} bs=512 seek=64 conv=fsync 2>/dev/null
dd if=${UBOOT_ITB} of=${TGT_DEV} bs=512 seek=16384 conv=fsync 2>/dev/null

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
    APPEND root=UUID=${ROOTFS_UUID} rootfstype=btrfs rootflags=compress=zstd:${ZSTD_LEVEL} console=ttyS2,1500000n8 console=tty0 earlycon=uart8250,mmio32,0xfe660000 init=/sbin/init rw
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