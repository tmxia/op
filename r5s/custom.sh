#!/bin/bash
# custom.sh - 自定义设置，在 OpenWrt 源码预处理后执行

set -e  # 遇到错误立即退出，便于调试

echo "=== Starting custom.sh ==="

# ========== 1. 备份当前 .config（如果存在） ==========
if [ -f .config ]; then
    cp .config .config.bak
    echo "Backed up .config to .config.bak"
fi

# ========== 2. 强制修正平台配置 ==========
echo "Fixing platform to rockchip..."

# 清除旧的平台配置
sed -i '/CONFIG_TARGET_mediatek/d' .config 2>/dev/null || true
sed -i '/CONFIG_TARGET_rockchip/d' .config 2>/dev/null || true

# 写入正确的平台配置
cat >> .config <<EOF
CONFIG_TARGET_rockchip=y
CONFIG_TARGET_rockchip_armv8=y
CONFIG_TARGET_rockchip_armv8_DEVICE_friendlyarm_nanopi-r5s=y
CONFIG_TARGET_ROOTFS_PARTSIZE=960
EOF

# ========== 3. 禁用可能出问题的内核模块 ==========
echo "Disabling kmod-crypto-sha512 and kernel crypto sha512..."
sed -i '/CONFIG_PACKAGE_kmod-crypto-sha512/d' .config
echo "CONFIG_PACKAGE_kmod-crypto-sha512=n" >> .config

# 禁用内核中的 SHA512 支持（避免模块编译）
sed -i '/CONFIG_CRYPTO_SHA512/d' .config
echo "CONFIG_CRYPTO_SHA512=n" >> .config

# ========== 4. 清理可能残留的 mediatek 目录或符号链接 ==========
echo "Cleaning up possible mediatek leftovers..."
rm -rf target/linux/mediatek 2>/dev/null || true
rm -rf build_dir/target-*_mediatek* 2>/dev/null || true

# ========== 5. 重新生成完整配置（确保依赖正确） ==========
echo "Running make defconfig to regenerate full config..."
make defconfig

# 可选：再次确保关键配置不被覆盖
echo "CONFIG_TARGET_rockchip=y" >> .config
echo "CONFIG_TARGET_rockchip_armv8=y" >> .config
echo "CONFIG_TARGET_rockchip_armv8_DEVICE_friendlyarm_nanopi-r5s=y" >> .config
echo "CONFIG_PACKAGE_kmod-crypto-sha512=n" >> .config
echo "CONFIG_CRYPTO_SHA512=n" >> .config

# 显示当前平台配置
echo "Current target after fix:"
grep CONFIG_TARGET_rockchip .config || echo "No rockchip config found"

# ========== 6. 网络配置修改 ==========
echo "Modifying network configuration..."
# 修改默认 IP 为 192.168.3.3
sed -i 's/192.168.1.1/192.168.3.3/g' package/base-files/files/bin/config_generate
sed -i 's/10.0.0.1/192.168.3.3/g' package/base-files/files/bin/config_generate

# 修改网关为 192.168.3.1
sed -i "s/option gateway '10.0.0.1'/option gateway '192.168.3.1'/g" package/base-files/files/bin/config_generate
sed -i "s/option gateway '192.168.1.1'/option gateway '192.168.3.1'/g" package/base-files/files/bin/config_generate

# 修改 DNS 为 192.168.3.1
sed -i "s/option dns '10.0.0.1'/option dns '192.168.3.1'/g" package/base-files/files/bin/config_generate
sed -i "s/option dns '192.168.1.1'/option dns '192.168.3.1'/g" package/base-files/files/bin/config_generate

# 同时修改网络配置文件（如果存在）
if [ -f package/base-files/files/etc/config/network ]; then
    sed -i 's/10.0.0.1/192.168.3.3/g' package/base-files/files/etc/config/network
    sed -i 's/192.168.1.1/192.168.3.3/g' package/base-files/files/etc/config/network
    sed -i "s/option gateway '10.0.0.1'/option gateway '192.168.3.1'/g" package/base-files/files/etc/config/network
    sed -i "s/option gateway '192.168.1.1'/option gateway '192.168.3.1'/g" package/base-files/files/etc/config/network
    sed -i "s/option dns '10.0.0.1'/option dns '192.168.3.1'/g" package/base-files/files/etc/config/network
    sed -i "s/option dns '192.168.1.1'/option dns '192.168.3.1'/g" package/base-files/files/etc/config/network
fi

# ========== 7. 其他自定义 ==========
echo "Applying other customizations..."
# 修改默认主题
sed -i 's/luci-theme-argon/luci-theme-bootstrap/g' feeds/luci/collections/luci/Makefile

# 修改主机名
sed -i 's/ImmortalWrt/r5s/g' package/base-files/files/bin/config_generate

# 添加 nikki 源（如果尚未添加）
if ! grep -q "nikki" feeds.conf; then
    echo 'src-git nikki https://github.com/nikkinikki-org/OpenWrt-nikki.git;main' >> feeds.conf
fi

# 更新 feeds（注意：可能会覆盖之前已安装的包，但需要）
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
  Pre-downloaded rule files for Nikki (geosite.dat and geoip.metadb)
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

# 下载规则文件
wget -O package/nikki-files/files/etc/nikki/run/geosite.dat https://cdn.uuiu.net/nikki/geosite.dat
wget -O package/nikki-files/files/etc/nikki/run/geoip.metadb https://cdn.uuiu.net/nikki/geoip.metadb
chmod 755 package/nikki-files/files/etc/nikki/run/geosite.dat
chmod 755 package/nikki-files/files/etc/nikki/run/geoip.metadb

# 可选：配置 pip 镜像
mkdir -p ~/.pip
cat > ~/.pip/pip.conf <<EOF
[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple
trusted-host = pypi.tuna.tsinghua.edu.cn
EOF

# 可选：安装 Python 包（忽略错误）
pip3 install requests telethon tqdm paramiko tailer flask-cors unrar pytz bleach beautifulsoup4 python-dateutil || true

echo "custom.sh executed successfully."