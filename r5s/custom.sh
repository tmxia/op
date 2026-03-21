#!/bin/bash
# 10-custom.sh - 自定义设置，在 OpenWrt 源码预处理后执行

# 修改默认 IP
sed -i 's/192.168.1.1/192.168.3.3/g' package/base-files/files/bin/config_generate

# 修改默认主题 (将 argon 改为 Bootstrap)
sed -i 's/luci-theme-argon/luci-theme-bootstrap/g' feeds/luci/collections/luci/Makefile

# 修改主机名
sed -i 's/ImmortalWrt/r5s/g' package/base-files/files/bin/config_generate

# 添加 nikki 源
echo 'src-git nikki https://github.com/nikkinikki-org/OpenWrt-nikki.git;main' >> feeds.conf

# 重新更新 feeds
./scripts/feeds update -a
./scripts/feeds install -a

# 创建 nikki-files 包（存放预下载的规则文件）
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

# 下载规则文件（请确保 URL 有效，可替换为其他源）
wget -O package/nikki-files/files/etc/nikki/run/geosite.dat https://cdn.uuiu.net/nikki/geosite.dat
wget -O package/nikki-files/files/etc/nikki/run/geoip.metadb https://cdn.uuiu.net/nikki/geoip.metadb
chmod 755 package/nikki-files/files/etc/nikki/run/geosite.dat
chmod 755 package/nikki-files/files/etc/nikki/run/geoip.metadb

# 配置 pip 镜像（加快 Python 包下载）
mkdir -p ~/.pip
cat > ~/.pip/pip.conf <<EOF
[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple
trusted-host = pypi.tuna.tsinghua.edu.cn
EOF

# 安装可能需要的 Python 包（可选，根据构建需要）
pip3 install requests telethon tqdm paramiko tailer flask-cors unrar pytz bleach beautifulsoup4 python-dateutil || true

echo "10-custom.sh executed successfully."