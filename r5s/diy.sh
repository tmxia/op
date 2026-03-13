#!/bin/bash

# Default IP
sed -i 's/192.168.1.1/192.168.3.3/g' package/base-files/files/bin/config_generate

# Modify default theme
# sed -i 's/luci-theme-design/luci-theme-Bootstrap/g' feeds/luci/collections/luci/Makefile
sed -i 's/luci-theme-argon/luci-theme-Bootstrap/g' feeds/luci/collections/luci/Makefile

# Change hostname (from ImmortalWrt to r5s)
sed -i 's/ImmortalWrt/r5s/g' package/base-files/files/bin/config_generate

# Git sparse clone (optional, unused)
git_sparse_clone() {
    分支="$1" repourl="$2" && shift 2
    git clone --depth=1 -b "$branch" --single-branch --filter=blob:none --sparse "$repourl"
    repodir=$(echo "$repourl" | awk -F '/' '{print $(NF)}')
    cd "$repodir" && git sparse-checkout set "$@"
    mv -f "$@" ../package
    cd .. && rm -rf "$repodir"
}

# Add package feeds
echo 'src-git nikki https://github.com/nikkinikki-org/OpenWrt-nikki.git;main' >> feeds.conf.default

# (Remove Amlogic cloning) No longer needed for Nanopi R5S
# git clone https://github.com/ophub/luci-app-amlogic --depth=1 clone/amlogic

# Create nikki rule files package
mkdir -p package/nikki-files/files/etc/nikki/run

# Create Makefile for nikki-files
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

# Download rule files into package directory
echo "Downloading rule files..."
wget -O package/nikki-files/files/etc/nikki/run/geosite.dat https://cdn.uuiu.net/nikki/geosite.dat
wget -O package/nikki-files/files/etc/nikki/run/geoip.metadb https://cdn.uuiu.net/nikki/geoip.metadb

# Set file permissions
chmod 755 package/nikki-files/files/etc/nikki/run/geosite.dat
chmod 755 package/nikki-files/files/etc/nikki/run/geoip.metadb

# (Removed feeds update for nikki-files – local package is automatically included)

# Pip3 config (for build dependencies)
mkdir -p ~/.pip
echo "[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple
trusted-host = pypi.tuna.tsinghua.edu.cn" > ~/.pip/pip.conf

# Install Python packages (needed by some build scripts)
pip3 install requests telethon tqdm paramiko tailer flask-cors unrar pytz bleach beautifulsoup4 python-dateutil

# Clean temporary clones (none left)
# rm -rf clone   (no longer needed)
