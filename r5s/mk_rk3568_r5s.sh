#!/bin/bash

echo "========================= begin $0 ==========================="
source make.env
source public_funcs
init_work_env

# 盒子型号识别参数
PLATFORM=rockchip
SOC=rk3568
BOARD=nanopi-r5s

# 5.10(及以上)内核是否启用WiFi（R5S无板载WiFi，默认禁用，如有M.2模块可启用）
ENABLE_WIFI_K510=0

SUBVER=$1

# Kernel image sources (确保 KERNEL_PKG_HOME 指向 rockchip 内核包)
###################################################################
KERNEL_TAGS="stable"
KERNEL_BRANCHES="mainline:all:>=:5.4"
MODULES_TGZ=${KERNEL_PKG_HOME}/modules-${KERNEL_VERSION}.tar.gz
check_file ${MODULES_TGZ}
BOOT_TGZ=${KERNEL_PKG_HOME}/boot-${KERNEL_VERSION}.tar.gz
check_file ${BOOT_TGZ}
DTBS_TGZ=${KERNEL_PKG_HOME}/dtb-rockchip-${KERNEL_VERSION}.tar.gz   # 注意 dtb 包名
check_file ${DTBS_TGZ}
K510=$(get_k510_from_boot_tgz "${BOOT_TGZ}" "vmlinuz-${KERNEL_VERSION}")
export K510
###########################################################################

# Openwrt root 源文件
OPWRT_ROOTFS_GZ=$(get_openwrt_rootfs_archive ${PWD})
check_file ${OPWRT_ROOTFS_GZ}
echo "Use $OPWRT_ROOTFS_GZ as openwrt rootfs!"

# 目标镜像文件
TGT_IMG="${WORK_DIR}/openwrt_${SOC}_${BOARD}_${OPENWRT_VER}_k${KERNEL_VERSION}${SUBVER}.img"

# 补丁和脚本（重新组织，针对 rk3568）
###########################################################################
KMOD="${PWD}/files/kmod"
KMOD_BLACKLIST="${PWD}/files/kmod_blacklist"
MAC_SCRIPT2="${PWD}/files/find_macaddr.pl"
MAC_SCRIPT3="${PWD}/files/inc_macaddr.pl"
CPUSTAT_SCRIPT="${PWD}/files/cpustat"
CPUSTAT_SCRIPT_PY="${PWD}/files/cpustat.py"
INDEX_PATCH_HOME="${PWD}/files/index.html.patches"
GETCPU_SCRIPT="${PWD}/files/getcpu"
FLIPPY="${PWD}/files/scripts_deprecated/flippy_cn"
BANNER="${PWD}/files/banner"

# 固件及配置文件（R5S 专用目录）
FMW_HOME="${PWD}/files/firmware"
SYSCTL_CUSTOM_CONF="${PWD}/files/99-custom.conf"

# R5S 专用配置
DAEMON_JSON="${PWD}/files/rk3568/daemon.json"               # Docker daemon 配置（若有）
BAL_CONFIG="${PWD}/files/rk3568/balance_irq"                # IRQ 平衡配置
CPUFREQ_INIT="${PWD}/files/rk3568/cpufreq"                  # CPU 调频配置
FORCE_REBOOT="${PWD}/files/rk3568/reboot"                   # 强制重启脚本（可选）
FIX_CPU_FREQ="${PWD}/files/fixcpufreq.pl"                   # 通用 CPU 频率修正脚本

# 20210302 modify (Rockchip U-Boot)
FIP_HOME="${PWD}/files/rk3568/uboot"                        # 存放 idbloader.img 和 u-boot.itb 的目录
UBOOT_IDBLOADER="${FIP_HOME}/idbloader.img"
UBOOT_ITB="${FIP_HOME}/u-boot.itb"

# 其他工具
SS_LIB="${PWD}/files/ss-glibc/lib-glibc.tar.xz"
SS_BIN="${PWD}/files/ss-glibc/armv8a_crypto/ss-bin-glibc.tar.xz"
JQ="${PWD}/files/jq"
DOCKERD_PATCH="${PWD}/files/dockerd.patch"
FIRMWARE_TXZ="${PWD}/files/firmware_armbian.tar.xz"
BOOTFILES_HOME="${PWD}/files/bootfiles/rockchip"            # 存放启动相关文件（如 boot.scr 等）
GET_RANDOM_MAC="${PWD}/files/get_random_mac.sh"
DOCKER_README="${PWD}/files/DockerReadme.pdf"
SYSINFO_SCRIPT="${PWD}/files/30-sysinfo.sh"
OPENWRT_INSTALL="${PWD}/files/openwrt-install-rockchip"     # 安装脚本（需针对 rockchip 修改）
OPENWRT_UPDATE="${PWD}/files/openwrt-update-rockchip"       # 更新脚本
OPENWRT_KERNEL="${PWD}/files/openwrt-kernel"
OPENWRT_BACKUP="${PWD}/files/openwrt-backup"
FIRSTRUN_SCRIPT="${PWD}/files/first_run.sh"
MODEL_DB="${PWD}/files/rockchip_model_database.txt"         # 设备数据库
P7ZIP="${PWD}/files/7z"
DDBR="${PWD}/files/openwrt-ddbr"
SSH_CIPHERS="aes128-gcm@openssh.com,aes256-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr,chacha20-poly1305@openssh.com"
SSHD_CIPHERS="aes128-gcm@openssh.com,aes256-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr"
###########################################################################

check_depends

SKIP_MB=4          # 起始跳过 4MiB（存放 idbloader）
BOOT_MB=256        # boot 分区 256MiB（存放内核、dtb、extlinux）
ROOTFS_MB=960      # 根文件系统大小，可调整
SIZE=$((SKIP_MB + BOOT_MB + ROOTFS_MB))
create_image "$TGT_IMG" "$SIZE"
create_partition "$TGT_DEV" "msdos" "$SKIP_MB" "$BOOT_MB" "fat32" "0" "-1" "btrfs"
make_filesystem "$TGT_DEV" "B" "fat32" "BOOT" "R" "btrfs" "ROOTFS"
mount_fs "${TGT_DEV}p1" "${TGT_BOOT}" "vfat"
mount_fs "${TGT_DEV}p2" "${TGT_ROOT}" "btrfs" "compress=zstd:${ZSTD_LEVEL}"
echo "创建 /etc 子卷 ..."
btrfs subvolume create $TGT_ROOT/etc
extract_rootfs_files
extract_rockchip_boot_files    # 需要自定义函数，或直接调用通用 extract_boot_files

# 写入 U-Boot 到磁盘开始位置（前 4MiB 保留）
echo "写入 U-Boot 到磁盘 ..."
dd if=${UBOOT_IDBLOADER} of=${TGT_DEV} bs=512 seek=64 conv=fsync 2>/dev/null
dd if=${UBOOT_ITB} of=${TGT_DEV} bs=512 seek=16384 conv=fsync 2>/dev/null

echo "修改引导分区相关配置 ... "
cd $TGT_BOOT

# 创建 extlinux 目录并生成配置文件（主线 U-Boot 标准方式）
mkdir -p extlinux
cat > extlinux/extlinux.conf <<EOF
LABEL OpenWrt
    KERNEL ../zImage
    FDT ../dtb/rockchip/rk3568-nanopi-r5s.dtb
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
adjust_getty_config
adjust_samba_config
adjust_openssh_config
# 不适用于 R5S 的步骤可注释掉，如 use_xrayplug_replace_v2rayplug
create_fstab_config
adjust_mosdns_config
patch_admin_status_index_html
adjust_kernel_env
copy_uboot_to_fs         # 如果需要将 uboot 文件复制到文件系统内（可选）
write_release_info
write_banner
config_first_run
create_snapshot "etc-000"

# 不再需要额外的写 uboot 操作，因为已经写入
clean_work_env
mv ${TGT_IMG} ${OUTPUT_DIR} && sync
echo "镜像已生成! 存放在 ${OUTPUT_DIR} 下面!"
echo "========================== end $0 ================================"
echo
