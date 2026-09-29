#!/bin/bash

# Default IP
sed -i 's/192.168.1.1/192.168.3.3/g' package/base-files/files/bin/config_generate

# Modify default theme
# sed -i 's/luci-theme-design/luci-theme-Bootstrap/g' feeds/luci/collections/luci/Makefile
sed -i 's/luci-theme-argon/luci-theme-Bootstrap/g' feeds/luci/collections/luci/Makefile

# Changing the host name
sed -i 's/ImmortalWrt/n1/g' package/base-files/files/bin/config_generate

# Git sparse clone
git_sparse_clone() {
    branch="$1" repourl="$2" && shift 2
    git clone --depth=1 -b "$branch" --single-branch --filter=blob:none --sparse "$repourl"
    repodir=$(echo "$repourl" | awk -F '/' '{print $(NF)}')
    cd "$repodir" && git sparse-checkout set "$@"
    mv -f "$@" ../package
    cd .. && rm -rf "$repodir"
}

# 添加源
echo 'src-git nikki https://github.com/nikkinikki-org/OpenWrt-nikki.git;main' >> feeds.conf.default

# Add packages
git clone https://github.com/ophub/luci-app-amlogic --depth=1 clone/amlogic
# git clone https://github.com/xiaorouji/openwrt-passwall --depth=1 clone/passwall

# Update packages
# rm -rf feeds/luci/applications/luci-app-passwall
# cp -rf clone/amlogic/luci-app-amlogic clone/passwall/luci-app-passwall feeds/luci/applications/
cp -rf clone/amlogic/luci-app-amlogic feeds/luci/applications/

# 创建nikki规则文件包目录
mkdir -p package/nikki-files/files/etc/nikki/run

# 创建Makefile
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

# 下载规则文件到包目录
echo "下载规则文件中..."
wget -O package/nikki-files/files/etc/nikki/run/geosite.dat https://cdn.uuiu.net/nikki/geosite.dat
wget -O package/nikki-files/files/etc/nikki/run/geoip.metadb https://cdn.uuiu.net/nikki/geoip.metadb

# 设置文件权限
chmod 755 package/nikki-files/files/etc/nikki/run/geosite.dat
chmod 755 package/nikki-files/files/etc/nikki/run/geoip.metadb

# 更新feeds并安装nikki-files包
./scripts/feeds update nikki-files
./scripts/feeds install -a -p nikki-files

# Pip3 conf
mkdir -p ~/.pip
echo "[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple
trusted-host = pypi.tuna.tsinghua.edu.cn" > ~/.pip/pip.conf

# Pip3 packages
pip3 install requests telethon tqdm paramiko tailer flask-cors unrar pytz bleach beautifulsoup4 python-dateutil

# Clean packages
rm -rf clone