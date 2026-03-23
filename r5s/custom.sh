#!/bin/bash
set -e
echo "=== Starting custom.sh (post-config) ==="

# 1. 删除所有 mediatek 残留（目录、符号链接、缓存）
echo "Deleting all mediatek related files..."
rm -rf target/linux/mediatek
rm -rf build_dir/target-*_mediatek*
rm -rf staging_dir/target-*_mediatek*
rm -rf tmp/.config-target-mediatek*
find . -name "*mediatek*" -type d -exec rm -rf {} \; 2>/dev/null || true

# 2. 确保 rockchip target 目录正确（不是符号链接）
echo "Ensuring rockchip target is correct..."
if [ -L target/linux/rockchip ]; then
    rm target/linux/rockchip
    git checkout HEAD -- target/linux/rockchip
elif [ ! -d target/linux/rockchip ]; then
    git checkout HEAD -- target/linux/rockchip
fi

# 3. 禁用可能修改平台的补丁脚本（重命名）
echo "Disabling problematic patches..."
for script in 01-prepare_base-mainline.sh 05-fix-source.sh; do
    if [ -f "$script" ]; then
        mv "$script" "${script}.disabled"
        echo "Disabled $script"
    fi
done

# 4. 强制修改 .config
echo "Fixing .config..."
sed -i '/CONFIG_TARGET_mediatek/d' .config
sed -i '/CONFIG_TARGET_rockchip/d' .config
cat >> .config <<EOF
CONFIG_TARGET_rockchip=y
CONFIG_TARGET_rockchip_armv8=y
CONFIG_TARGET_rockchip_armv8_DEVICE_friendlyarm_nanopi-r5s=y
CONFIG_TARGET_ROOTFS_PARTSIZE=960
CONFIG_PACKAGE_kmod-crypto-sha512=n
CONFIG_CRYPTO_SHA512=n
EOF

# 5. 运行 make defconfig 生成完整配置
echo "Running make defconfig..."
make defconfig

# 6. 再次强制修正（防止 defconfig 覆盖）
sed -i '/CONFIG_TARGET_mediatek/d' .config
sed -i '/CONFIG_TARGET_rockchip/d' .config
cat >> .config <<EOF
CONFIG_TARGET_rockchip=y
CONFIG_TARGET_rockchip_armv8=y
CONFIG_TARGET_rockchip_armv8_DEVICE_friendlyarm_nanopi-r5s=y
CONFIG_TARGET_ROOTFS_PARTSIZE=960
CONFIG_PACKAGE_kmod-crypto-sha512=n
CONFIG_CRYPTO_SHA512=n
EOF

# 7. 清理构建目录（确保没有残留）
echo "Cleaning build directories..."
make target/linux/clean
rm -rf build_dir staging_dir tmp

# 8. 显示最终状态（调试）
echo "=== Final target/linux directory ==="
ls -la target/linux/ | grep -E "rockchip|mediatek"
echo "=== Final .config platform ==="
grep CONFIG_TARGET_rockchip .config || echo "No rockchip config found"

# 9. 网络配置修改（保留你的自定义）
echo "Modifying network configuration..."
sed -i 's/192.168.1.1/192.168.3.3/g' package/base-files/files/bin/config_generate
sed -i 's/10.0.0.1/192.168.3.3/g' package/base-files/files/bin/config_generate
sed -i "s/option gateway '10.0.0.1'/option gateway '192.168.3.1'/g" package/base-files/files/bin/config_generate
sed -i "s/option gateway '192.168.1.1'/option gateway '192.168.3.1'/g" package/base-files/files/bin/config_generate
sed -i "s/option dns '10.0.0.1'/option dns '192.168.3.1'/g" package/base-files/files/bin/config_generate
sed -i "s/option dns '192.168.1.1'/option dns '192.168.3.1'/g" package/base-files/files/bin/config_generate

# 10. 其他自定义（主题、主机名、nikki 等）
echo "Applying other customizations..."
sed -i 's/luci-theme-argon/luci-theme-bootstrap/g' feeds/luci/collections/luci/Makefile
sed -i 's/ImmortalWrt/r5s/g' package/base-files/files/bin/config_generate

if ! grep -q "nikki" feeds.conf; then
    echo 'src-git nikki https://github.com/nikkinikki-org/OpenWrt-nikki.git;main' >> feeds.conf
fi

./scripts/feeds update -a
./scripts/feeds install -a

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

mkdir -p ~/.pip
cat > ~/.pip/pip.conf <<EOF
[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple
trusted-host = pypi.tuna.tsinghua.edu.cn
EOF
pip3 install requests telethon tqdm paramiko tailer flask-cors unrar pytz bleach beautifulsoup4 python-dateutil || true

echo "custom.sh executed successfully."