#!/bin/bash

# Default IP
sed -i 's/192.168.1.1/192.168.3.3/g' package/base-files/files/bin/config_generate

# Modify default theme
sed -i 's/luci-theme-argon/luci-theme-Bootstrap/g' feeds/luci/collections/luci/Makefile

# Changing the host name
sed -i 's/ImmortalWrt/r5s/g' package/base-files/files/bin/config_generate

# 添加源
echo 'src-git nikki https://github.com/nikkinikki-org/OpenWrt-nikki.git;main' >> feeds.conf.default

# Add packages - 保留 Amlogic 工具
git clone https://github.com/ophub/luci-app-amlogic --depth=1 clone/amlogic
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

# ==================== 修复点 2：带重试的规则文件下载 ====================
echo "下载规则文件中..."
GEO_MIRRORS=(
  "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat"
  "https://cdn.uuiu.net/nikki/geosite.dat"
)
GEOIP_MIRRORS=(
  "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.metadb"
  "https://cdn.uuiu.net/nikki/geoip.metadb"
)

download_with_retry() {
  local out=$1; shift
  for url in "$@"; do
    for i in 1 2 3; do
      if wget -q --timeout=30 -O "$out" "$url"; then
        if [ -s "$out" ]; then
          echo "下载成功: $url"
          return 0
        fi
      fi
      echo "重试 ($i/3): $url"
      sleep 3
    done
  done
  echo "警告: 所有镜像下载失败: $out"
  return 1
}

download_with_retry package/nikki-files/files/etc/nikki/run/geosite.dat "${GEO_MIRRORS[@]}" || true
download_with_retry package/nikki-files/files/etc/nikki/run/geoip.metadb "${GEOIP_MIRRORS[@]}" || true

# 检查文件大小，如果过小就创建一个占位符，避免安装脚本报错
for f in package/nikki-files/files/etc/nikki/run/geosite.dat \
         package/nikki-files/files/etc/nikki/run/geoip.metadb; do
  [ -f "$f" ] && [ -s "$f" ] || { echo "占位: $f"; touch "$f"; }
  chmod 755 "$f"
done

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