#!/bin/bash

echo "========================= begin $0 ==========================="
source make.env
source public_funcs
init_work_env

# 盒子型号识别参数
PLATFORM=rockchip
SOC=rk3568
BOARD=r5s

SUBVER=$1

# Kernel image sources
KERNEL_TAGS="stable"
KERNEL_BRANCHES="mainline:all:>=:5.4"
MODULES_TGZ=${KERNEL_PKG_HOME}/modules-${KERNEL_VERSION}.tar.gz
check_file ${MODULES_TGZ}
BOOT_TGZ=${KERNEL_PKG_HOME}/boot-${KERNEL_VERSION}.tar.gz
check_file ${BOOT_TGZ}
DTBS_TGZ=${KERNEL_PKG_HOME}/dtb-rockchip-${KERNEL_VERSION}.tar.gz
check_file ${DTBS_TGZ}

# Openwrt root 源文件
OPWRT_ROOTFS_GZ=$(get_openwrt_rootfs_archive ${PWD})
check_file ${OPWRT_ROOTFS_GZ}
echo "Use $OPWRT_ROOTFS_GZ as openwrt rootfs!"

# 目标镜像文件
TGT_IMG="${WORK_DIR}/openwrt_${SOC}_${BOARD}_${OPENWRT_VER}_k${KERNEL_VERSION}${SUBVER}.img"

# 补丁和脚本
KMOD="${PWD}/files/kmod"
KMOD_BLACKLIST="${PWD}/files/kmod_blacklist"
CPUSTAT_SCRIPT="${PWD}/files/cpustat"
CPUSTAT_SCRIPT_PY="${PWD}/files/cpustat.py"
INDEX_PATCH_HOME="${PWD}/files/index.html.patches"
GETCPU_SCRIPT="${PWD}/files/getcpu"
FLIPPY="${PWD}/files/scripts_deprecated/flippy_cn"
BANNER="${PWD}/files/banner"

FMW_HOME="${PWD}/files/firmware"
SYSCTL_CUSTOM_CONF="${PWD}/files/99-custom.conf"
DAEMON_JSON="${PWD}/files/rk3568/daemon.json"
FORCE_REBOOT="${PWD}/files/rk3568/reboot"
BAL_ETH_IRQ="${PWD}/files/balethirq.pl"
FIX_CPU_FREQ="${PWD}/files/fixcpufreq.pl"
SYSFIXTIME_PATCH="${PWD}/files/sysfixtime.patch"
SSL_CNF_PATCH="${PWD}/files/openssl_engine.patch"
BAL_CONFIG="${PWD}/files/rk3568/balance_irq"
CPUFREQ_INIT="${PWD}/files/rk3568/cpufreq"
DOCKERD_PATCH="${PWD}/files/dockerd.patch"
FIRMWARE_TXZ="${PWD}/files/firmware_armbian.tar.xz"
BOOTFILES_HOME="${PWD}/files/bootfiles/rockchip"
GET_RANDOM_MAC="${PWD}/files/get_random_mac.sh"
DOCKER_README="${PWD}/files/DockerReadme.pdf"
SYSINFO_SCRIPT="${PWD}/files/30-sysinfo.sh"
OPENWRT_INSTALL="${PWD}/files/openwrt-install-amlogic"
OPENWRT_UPDATE="${PWD}/files/openwrt-update-amlogic"
OPENWRT_KERNEL="${PWD}/files/openwrt-kernel"
OPENWRT_BACKUP="${PWD}/files/openwrt-backup"
FIRSTRUN_SCRIPT="${PWD}/files/first_run.sh"
MODEL_DB="${PWD}/files/rockchip_model_database.txt"
P7ZIP="${PWD}/files/7z"
DDBR="${PWD}/files/openwrt-ddbr"
SSH_CIPHERS="aes128-gcm@openssh.com,aes256-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr,chacha20-poly1305@openssh.com"
SSHD_CIPHERS="aes128-gcm@openssh.com,aes256-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr"

check_depends

SKIP_MB=16
BOOT_MB=256
ROOTFS_MB=1024
SIZE=$((SKIP_MB + BOOT_MB + ROOTFS_MB))
create_image "$TGT_IMG" "$SIZE"
create_partition "$TGT_DEV" "msdos" "$SKIP_MB" "$BOOT_MB" "fat32" "0" "-1" "btrfs"
make_filesystem "$TGT_DEV" "B" "fat32" "BOOT" "R" "btrfs" "ROOTFS"
mount_fs "${TGT_DEV}p1" "${TGT_BOOT}" "vfat"
mount_fs "${TGT_DEV}p2" "${TGT_ROOT}" "btrfs" "compress=zstd:${ZSTD_LEVEL}"
echo "创建 /etc 子卷 ..."
btrfs subvolume create $TGT_ROOT/etc
extract_rootfs_files

# ==================== 修复点 1：自己实现 boot 提取，绕开 public_funcs 的 bug ====================
echo "释放 Kernel zImage、uInitrd 及 dtbs 压缩包 ..."
tar -xzf ${BOOT_TGZ} -C ${TGT_BOOT}/
tar -xzf ${DTBS_TGZ} -C ${TGT_BOOT}/
# 复制 bootloader（使用 cp -rf，注意 -r 参数）
cp -rf ${BOOTFILES_HOME}/${SOC}/* ${TGT_BOOT}/ 2>/dev/null || true
echo "释放 boot 文件完成"

echo "修改引导分区相关配置 ... "
cd $TGT_BOOT
rm -f uEnv.ini
cat >uEnv.txt <<EOF
LINUX=/zImage
INITRD=/uInitrd

# 用于 FriendlyWrt R5S
FDT=/dtb/rockchip/rk3568-nanopi-r5s.dtb

APPEND=root=UUID=${ROOTFS_UUID} rootfstype=btrfs rootflags=compress=zstd:${ZSTD_LEVEL} console=ttyS2,1500000n8 console=tty0 no_console_suspend consoleblank=0 fsck.fix=yes fsck.repair=yes net.ifnames=0 cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory swapaccount=1
EOF

echo "uEnv.txt -->"
echo "==============================================================================="
cat uEnv.txt
echo "==============================================================================="
echo

echo "修改根文件系统相关配置 ... "
cd $TGT_ROOT
copy_supplement_files
extract_glibc_programs
adjust_docker_config
adjust_openssl_config
adjust_getty_config
adjust_openssh_config
create_fstab_config
patch_admin_status_index_html
adjust_kernel_env
copy_uboot_to_fs
write_release_info
write_banner
config_first_run
create_snapshot "etc-000"
write_uboot_to_disk
clean_work_env
mv ${TGT_IMG} ${OUTPUT_DIR} && sync
echo "镜像已生成! 存放在 ${OUTPUT_DIR} 下面!"
echo "========================== end $0 ================================"