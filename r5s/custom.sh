#!/bin/bash
# custom.sh - 彻底修正平台和禁用问题模块，清理残留缓存

set -e
echo "=== Starting custom.sh (post-config) ==="

# ========== 1. 清理所有构建缓存 ==========
echo "Cleaning build directories to remove mediatek leftovers..."
rm -rf build_dir staging_dir tmp
mkdir -p build_dir staging_dir tmp

# ========== 2. 恢复正确的 target/linux/rockchip 目录 ==========
echo "Restoring target/linux/rockchip from git..."
# 如果 rockchip 是符号链接或目录被删除，强制从 git 恢复
if [ -L target/linux/rockchip ] || [ ! -d target/linux/rockchip ]; then
    rm -f target/linux/rockchip 2>/dev/null || true
    git checkout HEAD -- target/linux/rockchip 2>/dev/null || git checkout target/linux/rockchip
    echo "Restored target/linux/rockchip from git."
fi

# 删除所有可能残留的 mediatek 目录
echo "Removing mediatek leftovers..."
rm -rf target/linux/mediatek 2>/dev/null || true
rm -rf build_dir/target-*_mediatek* 2>/dev/null || true
rm -rf staging_dir/target-*_mediatek* 2>/dev/null || true

# ========== 3. 强制修正 .config 平台配置 ==========
echo "Fixing platform to rockchip in .config..."
sed -i '/CONFIG_TARGET_mediatek/d' .config
sed -i '/CONFIG_TARGET_rockchip/d' .config
cat >> .config <<EOF
CONFIG_TARGET_rockchip=y
CONFIG_TARGET_rockchip_armv8=y
CONFIG_TARGET_rockchip_armv8_DEVICE_friendlyarm_nanopi-r5s=y
CONFIG_TARGET_ROOTFS_PARTSIZE=960
EOF

# ========== 4. 禁用 kmod-crypto-sha512 和内核 SHA512 模块 ==========
echo "Disabling kmod-crypto-sha512 and kernel crypto sha512..."
sed -i '/CONFIG_PACKAGE_kmod-crypto-sha512/d' .config
echo "CONFIG_PACKAGE_kmod-crypto-sha512=n" >> .config
sed -i '/CONFIG_CRYPTO_SHA512/d' .config
echo "CONFIG_CRYPTO_SHA512=n" >> .config

# ========== 5. 重新生成完整配置 ==========
echo "Running make defconfig to regenerate full config..."
make defconfig

# 再次强制锁定平台（防止 defconfig 时被覆盖）
echo "Re-locking platform after defconfig..."
sed -i '/CONFIG_TARGET_mediatek/d' .config
sed -i '/CONFIG_TARGET_rockchip/d' .config
cat >> .config <<EOF
CONFIG_TARGET_rockchip=y
CONFIG_TARGET_rockchip_armv8=y
CONFIG_TARGET_rockchip_armv8_DEVICE_friendlyarm_nanopi-r5s=y
CONFIG_TARGET_ROOTFS_PARTSIZE=960
EOF

# 确保禁用 sha512 模块
sed -i '/CONFIG_PACKAGE_kmod-crypto-sha512/d' .config
echo "CONFIG_PACKAGE_kmod-crypto-sha512=n" >> .config

# ========== 6. 显示当前平台（调试用） ==========
echo "Current target after fix:"
grep CONFIG_TARGET_rockchip .config || echo "No rockchip config found"
echo "Target/linux directory listing:"
ls -la target/linux/ | grep -E "rockchip|mediatek" || echo "No rockchip or mediatek found"

# ========== 7. 网络配置修改 ==========
echo "Modifying network configuration..."
sed -i 's/192.168.1.1/192.168.3.3/g' package/base-files/files/bin/config_generate
sed -i 's/10.0.0.1/192.168.3.3/g' package/base-files/files/bin/config_generate
sed -i "s/option gateway '10.0.0.1'/option gateway '192.168.3.1'/g" package/base-files/files/bin/config_generate
sed -i "s/option gateway '192.168.1.1'/option gateway '192.168.3.1'/g" package/base-files/files/bin/config_generate
sed -i "s/option dns '10.0.0.1'/option dns '192.168.3.1'/g" package/base-files/files/bin/config_generate
sed -i "s/option dns '192.168.1.1'/option dns '192.168.3.1'/g" package/base-files/files/bin/config_generate

if [ -f package/base-files/files/etc/config/network ]; then
    sed -i 's/10.0.0.1/192.168.3.3/g' package/base-files/files/etc/config/network
    sed -i 's/192.168.1.1/192.168.3.3/g' package/base-files/files/etc/config/network
    sed -i "s/option gateway '10.0.0.1'/option gateway '192.168.3.1'/g" package/base-files/files/etc/config/network
    sed -i "s/option gateway '192.168.1.1'/option gateway '192.168.3.1'/g" package/base-files/files/etc/config/network
    sed -i "s/option dns '10.0.0.1'/option dns '192.168.3.1'/g" package/base-files/files/etc/config/network
    sed -i "s/option dns '192.168.1.1'/option dns '192.168.3.1'/g" package/base-files/files/etc/config/network
fi

# ========== 8. 其他自定义（主题、主机名、nikki 源等） ==========
echo "Applying other customizations..."
sed -i 's/luci-theme-argon/luci-theme-bootstrap/g' feeds/luci/collections/luci/Makefile
sed -i 's/ImmortalWrt/r5s/g' package/base-files/files/bin/config_generate

# 添加 nikki 源（如果不存在）
if ! grep -q "nikki" feeds.conf; then
    echo 'src-git nikki https://github.com/nikkinikki-org/OpenWrt-nikki.git;main' >> feeds.conf
fi

# 更新 feeds
./scripts/feeds update -a
./scripts/feeds install -a

# 创建 nikki-files 包
mkdir -p package/nikki-files/files/etc/nikki/run
cat > package/nikki-files/Makefile << 'EOF'
include $(TOPDIR)/rules.mk
PKG_NAME:=nikki-files
PKG_VERSION:=1.0
PKG_RELEASE:=1
include $(INCLUDE_DIR)/package.mk
define Package/nikki-files
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Nikki rule files
endef
define Package/nikki-files/description
  Pre-downloaded rule files for Nikki
endef
define Build/Prepare
endef
define Build/Configure
endef
define Build/Compile
endef
define Package/nikki-files/install
	$(INSTALL_DIR) $(1)/etc/nikki/run
	$(INSTALL_DATA) ./files/etc/nikki/run/geosite.dat $(1)/etc/nikki/run/
	$(INSTALL_DATA) ./files/etc/nikki/run/geoip.metadb $(1)/etc/nikki/run/
endef
$(eval $(call BuildPackage,nikki-files))
EOF

wget -O package/nikki-files/files/etc/nikki/run/geosite.dat https://cdn.uuiu.net/nikki/geosite.dat
wget -O package/nikki-files/files/etc/nikki/run/geoip.metadb https://cdn.uuiu.net/nikki/geoip.metadb
chmod 755 package/nikki-files/files/etc/nikki/run/geosite.dat
chmod 755 package/nikki-files/files/etc/nikki/run/geoip.metadb

# pip 镜像（可选）
mkdir -p ~/.pip
cat > ~/.pip/pip.conf <<EOF
[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple
trusted-host = pypi.tuna.tsinghua.edu.cn
EOF
pip3 install requests telethon tqdm paramiko tailer flask-cors unrar pytz bleach beautifulsoup4 python-dateutil || true

echo "custom.sh executed successfully."