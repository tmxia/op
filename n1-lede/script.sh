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
# Default IP
sed -i 's/192.168.1.1/192.168.3.3/g' package/base-files/files/bin/config_generate
# wireless
#rm -rf files/etc/config/wireless
#rm -rf files/etc/modules.d/wireless_enable
# Firewall custom
#echo "iptables -t nat -I POSTROUTING -o eth0 -j MASQUERADE" >> package/network/config/firewall/files/firewall.user
# geodata
#wget -q -cP files/usr/share/v2ray https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat
#wget -q -cP files/usr/share/v2ray https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat
# Add luci-theme-opentomcat
#svn co https://github.com/Leo-Jo-My/luci-theme-opentomcat.git package/lean/luci-theme-opentomcat
# Add luci-theme-argon
#rm -rf package/lean/luci-theme-argon
#git clone -b 18.06 https://github.com/jerrykuku/luci-theme-argon.git package/lean/luci-theme-argon
#Add amlogic管理
downloadSpecificDir 'https://github.com/ophub/luci-app-amlogic.git' 'main' 'package/lean/luci-app-amlogic'
#Add luci-app-passwall
git clone -b luci https://github.com/xiaorouji/openwrt-passwall.git package/lean/luci-app-passwall
# Update packages
rm -rf feeds/luci/applications/luci-app-passwall
cp -rf clone/amlogic/luci-app-amlogic clone/passwall/luci-app-passwall feeds/luci/applications/
#Add openclash
#svn co https://github.com/vernesong/OpenClash/trunk/luci-app-openclash package/lean/luci-app-openclash
#Add smartdns
downloadSpecificDir 'https://github.com/o0HalfLife0o/openwrt-ipk.git' 'master' 'package/lean/smartdns'
#Add luci-app-smartdns
#git clone -b lede https://github.com/pymumu/luci-app-smartdns.git package/lean/luci-app-smartdns
#Add luci-app-adguardhome
#git clone https://github.com/rufengsuixing/luci-app-adguardhome.git package/lean/luci-app-adguardhome
#sed -i '/packages/s#coolsnowwolf#o0HalfLife0o#' feeds.conf.default
# Pip3 conf
mkdir -p ~/.pip
echo "[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple
trusted-host = pypi.tuna.tsinghua.edu.cn" > ~/.pip/pip.conf
# Pip3 packages
pip3 install requests telethon tqdm paramiko tailer flask-cors unrar pytz bleach beautifulsoup4 python-dateutil docker
# Clean packages
rm -rf clone
# fix xray-core
rm -rf feeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang -b 22.x feeds/packages/lang/golang
