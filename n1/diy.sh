#!/bin/bash

# Default IP
sed -i 's/192.168.1.1/192.168.3.3/g' package/base-files/files/bin/config_generate

# Git sparse clone
git_sparse_clone() {
    branch="$1" repourl="$2" && shift 2
    git clone --depth=1 -b "$branch" --single-branch --filter=blob:none --sparse "$repourl"
    repodir=$(echo "$repourl" | awk -F '/' '{print $(NF)}')
    cd "$repodir" && git sparse-checkout set "$@"
    mv -f "$@" ../package
    cd .. && rm -rf "$repodir"
}

# Modify default theme
sed -i 's/luci-theme-design/luci-theme-Bootstrap/g' feeds/luci/collections/luci/Makefile
sed -i 's/luci-theme-argon/luci-theme-Bootstrap/g' feeds/luci/collections/luci/Makefile

# Changing the host name
sed -i 's/ImmortalWrt/n1/g' package/base-files/files/bin/config_generate

# Add packages
git clone --single-branch --depth=1 https://github.com/ophub/luci-app-amlogic package/luci-app-amlogic
git clone https://github.com/xiaorouji/openwrt-passwall --depth=1 clone/passwall

# Update packages
rm -rf feeds/luci/applications/luci-app-passwall
cp -rf clone/amlogic/luci-app-amlogic clone/passwall/luci-app-passwall feeds/luci/applications/

# Clean packages
rm -rf clone

# Pip3 conf
mkdir -p /root/.pip
echo "[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple
trusted-host = pypi.tuna.tsinghua.edu.cn" > /root/.pip/pip.conf

