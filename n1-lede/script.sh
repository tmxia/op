#!/bin/bash
cd openwrt
downloadSpecificDir(){
	url=$1
	branch=$2
	path=${3%/*}
	dir=${3##*/}
	rm -rf $path/.git $path/$dir
	git init $path
	cur_path=$(pwd)
	cd $path
	git remote add origin $url
	git config core.sparsecheckout true
	echo "$dir/" >> .git/info/sparse-checkout
	git pull origin $branch
	rm -rf .git
	cd $cur_path
}

# 替换默认IP
sed -i 's#192.168.1.1#192.168.3.3#g' package/base-files/files/bin/config_generate

# cpufreq
sed -i 's/LUCI_DEPENDS.*/LUCI_DEPENDS:=\@\(arm\|\|aarch64\)/g' feeds/luci/applications/luci-app-cpufreq/Makefile
sed -i 's/services/system/g' feeds/luci/applications/luci-app-cpufreq/luasrc/controller/cpufreq.lua

# 升级大雕的rust源码到官方最新版本1.85.1
sed -i 's/PKG_VERSION:=1.84.0/PKG_VERSION:=1.85.1/' feeds/packages/lang/rust/Makefile
sed -i 's/PKG_HASH:=15cee7395b07ffde022060455b3140366ec3a12cbbea8f1ef2ff371a9cca51bf/PKG_HASH:=0f2995ca083598757a8d9a293939e569b035799e070f419a686b0996fb94238a/' feeds/packages/lang/rust/Makefile

# 移除 lede feeds 自带的番茄核心包
rm -rf feeds/packages/net/xray-core
rm -rf feeds/packages/net/v2ray-geodata
rm -rf feeds/packages/net/sing-box
rm -rf feeds/packages/net/chinadns-ng
rm -rf feeds/packages/net/dns2socks
# rm -rf feeds/packages/net/dns2tcp
rm -rf feeds/packages/net/microsocks
cp -r feeds/passwall_packages/xray-core feeds/packages/net
cp -r feeds/passwall_packages/v2ray-geodata feeds/packages/net
cp -r feeds/passwall_packages/sing-box feeds/packages/net
cp -r feeds/passwall_packages/chinadns-ng feeds/packages/net
cp -r feeds/passwall_packages/dns2socks feeds/packages/net
# cp -r feeds/passwall_packages/dns2tcp feeds/packages/net
cp -r feeds/passwall_packages/microsocks feeds/packages/net

# 修改golang源码以编译xray1.8.8+版本
rm -rf feeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang -b 24.x feeds/packages/lang/golang
sed -i '/-linkmode external \\/d' feeds/packages/lang/golang/golang-package.mk

# 修改tailscale版本为官网最新v1.80.3 https://github.com/tailscale/tailscale 格式：https://codeload.github.com/tailscale/tailscale/tar.gz/v$(PKG_VERSION)?
sed -i 's/PKG_VERSION:=1.76.1/PKG_VERSION:=1.80.3/' feeds/packages/net/tailscale/Makefile
sed -i 's/PKG_HASH:=ce87e52fd4e8e52540162a2529c5d73f5f76c6679147a7887058865c9e01ec36/PKG_HASH:=4ea7d4c1a4e86905f330f5d5f5288488cb29d6c586d5bcabf9d02c5481ba740d/' feeds/packages/net/tailscale/Makefile
rm -rf feeds/packages/net/tailscale/patches

# 跟随最新版naiveproxy
rm -rf feeds/passwall_packages/naiveproxy
rm -rf feeds/helloworld/naiveproxy
git clone -b v5 https://github.com/sbwml/openwrt_helloworld.git
cp -r openwrt_helloworld/naiveproxy feeds/passwall_packages
cp -r openwrt_helloworld/naiveproxy feeds/helloworld

# 科学上网插件依赖
wget https://codeload.github.com/vernesong/OpenClash/zip/refs/heads/master -O OpenClash.zip
unzip OpenClash.zip
cp -r OpenClash-master/luci-app-openclash package/
rm -rf OpenClash.zip OpenClash-master
# 编译 po2lmo (如果有po2lmo可跳过)
pushd package/luci-app-openclash/tools/po2lmo
make && sudo make install
popd

# 添加luci-app-amlogic / 晶晨宝盒
git clone https://github.com/ophub/luci-app-amlogic.git
cp -r luci-app-amlogic/luci-app-amlogic package/luci-app-amlogic
rm -rf luci-app-amlogic

#添加smartdns
git clone https://github.com/kiddin9/smartdns-le package/smartdns-le
git clone https://github.com/kenzok8/openwrt-packages.git
cp -r openwrt-packages/luci-app-smartdns package/luci-app-smartdns
rm -rf openwrt-packages
sed -i 's/PKG_VERSION:=.*/PKG_VERSION:=1.2021.34/' feeds/packages/net/smartdns/Makefile
sed -i 's/PKG_SOURCE_VERSION:=.*/PKG_SOURCE_VERSION:=756029f5e9879075c042030bd3aa3db06d700270/' feeds/packages/net/smartdns/Makefile
sed -i 's/PKG_MIRROR_HASH:=.*/PKG_MIRROR_HASH:=c2979d956127946861977781beb3323ad9a614ae55014bc99ad39beb7a27d481/' feeds/packages/net/smartdns/Makefile

# Pip3 conf
mkdir -p ~/.pip
echo "[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple
trusted-host = pypi.tuna.tsinghua.edu.cn" > ~/.pip/pip.conf

# Pip3 packages
pip3 install requests telethon tqdm paramiko tailer flask-cors unrar pytz bleach beautifulsoup4 python-dateutil docker

#修改makefile
find package/*/ -maxdepth 2 -path "*/Makefile" | xargs -i sed -i 's/include\ \.\.\/\.\.\/luci\.mk/include \$(TOPDIR)\/feeds\/luci\/luci\.mk/g' {}
find package/*/ -maxdepth 2 -path "*/Makefile" | xargs -i sed -i 's/include\ \.\.\/\.\.\/lang\/golang\/golang\-package\.mk/include \$(TOPDIR)\/feeds\/packages\/lang\/golang\/golang\-package\.mk/g' {}
find package/*/ -maxdepth 2 -path "*/Makefile" | xargs -i sed -i 's/PKG_SOURCE_URL:=\@GHREPO/PKG_SOURCE_URL:=https:\/\/github\.com/g' {}
find package/*/ -maxdepth 2 -path "*/Makefile" | xargs -i sed -i 's/PKG_SOURCE_URL:=\@GHCODELOAD/PKG_SOURCE_URL:=https:\/\/codeload\.github\.com/g' {}

#修改xfsprogs的Makefile
sed -i 's/TARGET_CFLAGS += -DHAVE_MAP_SYNC/TARGET_CFLAGS += -DHAVE_MAP_SYNC -D_LARGEFILE64_SOURCE/' feeds/packages/utils/xfsprogs/Makefile
