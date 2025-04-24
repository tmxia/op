#!/bin/bash
# Git稀疏克隆，只克隆指定目录到本地
function git_sparse_clone() {
  branch="$1" repourl="$2" && shift 2
  git clone --depth=1 -b $branch --single-branch --filter=blob:none --sparse $repourl
  repodir=$(echo $repourl | awk -F '/' '{print $(NF)}')
  cd $repodir && git sparse-checkout set $@
  mv -f $@ ../package
  cd .. && rm -rf $repodir
}

###########################################################################
# 自定义添加
# git clone --depth=1 https://github.com/vernesong/OpenClash package/OpenClash
# git clone --depth=1 https://github.com/tty228/luci-app-wechatpush package/luci-app-wechatpush
# git clone --depth=1 https://github.com/sundaqiang/openwrt-packages package/openwrt-packages
# mv package/openwrt-packages/luci-app-wolplus package/luci-app-wolplus
# rm -rf package/openwrt-packages
# git clone --depth=1 https://github.com/kuoruan/openwrt-frp package/openwrt-frp
# git clone --depth=1 https://github.com/superzjg/luci-app-frpc_frps package/luci-app-frpc_frps
# git clone --depth=1 https://github.com/gw826943555/openwrt_msd_lite package/openwrt_msd_lite
# git clone --depth=1 https://github.com/riverscn/openwrt-iptvhelper package/openwrt-iptvhelper
###########################################################################
# Add packages
# git clone --depth 1 https://github.com/brvphoenix/wrtbwmon package/wrtbwmon
# git clone --depth 1 https://github.com/brvphoenix/luci-app-wrtbwmon package/luci-app-wrtbwmon

# git clone --depth=1 https://github.com/ximiTech/msd_lite package/msd_lite
# git clone --depth=1 https://github.com/ximiTech/luci-app-msd_lite package/luci-app-msd_lite

# git clone --depth=1 https://github.com/kenzok8/small-package package/small
# mv package/small/luci-app-openclash package/luci-app-openclash
# mv package/small/iptvhelper package/iptvhelper
# mv package/small/luci-app-iptvhelper package/luci-app-iptvhelper
# mv package/small/luci-app-timecontrol package/luci-app-timecontrol
# mv package/small/cdnspeedtest package/cdnspeedtest
# mv package/small/luci-app-cloudflarespeedtest package/luci-app-cloudflarespeedtest
# mv package/small/luci-app-dnsfilter package/luci-app-dnsfilter
mv package/small/luci-app-fileassistant package/luci-app-fileassistant
# rm -rf feeds/luci/applications/luci-app-wol
# mv package/small/luci-app-wolplus feeds/luci/applications/luci-app-wolplus
# mv package/small/luci-app-msd_lite package/luci-app-msd_lite
# mv package/small/netdata package/netdata
# mv package/small/luci-app-netdata package/luci-app-netdata
# mv package/small/qbittorrent package/qbittorrent
# mv package/small/qt6base package/qt6base
# mv package/small/qt6tools package/qt6tools
# mv package/small/rblibtorrent package/rblibtorrent
# mv package/small/luci-app-qbittorrent package/luci-app-qbittorrent
# mv package/small/luci-app-wechatpush package/luci-app-wechatpush
mv package/small/luci-app-poweroff package/luci-app-poweroff
# mv package/small/wrtbwmon package/wrtbwmon
# mv package/small/luci-app-wrtbwmon package/luci-app-wrtbwmon
rm -rf package/small
#添加科学上网源
git clone --depth=1 https://github.com/xiaorouji/openwrt-passwall-packages package/openwrt-passwall-packages
git clone --depth=1 https://github.com/xiaorouji/openwrt-passwall package/openwrt-passwall
git clone -b 18.06 --single-branch --depth 1 https://github.com/jerrykuku/luci-theme-argon package/luci-theme-argon
git clone -b 18.06 --single-branch --depth 1 https://github.com/jerrykuku/luci-app-argon-config package/luci-app-argon-config
git clone --depth=1 https://github.com/ophub/luci-app-amlogic package/amlogic
git clone --depth=1 https://github.com/sirpdboy/luci-app-ddns-go package/ddnsgo
# git clone --depth=1 https://github.com/sirpdboy/NetSpeedTest package/NetSpeedTest

git clone -b v5-lua --single-branch --depth 1 https://github.com/sbwml/luci-app-mosdns package/mosdns
# git clone -b lua --single-branch --depth 1 https://github.com/sbwml/luci-app-alist package/alist
# git clone --depth=1 https://github.com/gdy666/luci-app-lucky.git package/lucky

# Remove packages
#删除lean库中的插件，使用自定义源中的包。
rm -rf feeds/packages/net/v2ray-geodata
rm -rf feeds/luci/themes/luci-theme-argon
rm -rf feeds/luci/applications/luci-app-argon-config
rm -rf feeds/packages/net/mosdns
rm -rf feeds/packages/utils/v2dat
rm -rf feeds/luci/applications/luci-app-mosdns
#rm -rf feeds/luci/themes/luci-theme-design
#rm -rf feeds/luci/applications/luci-app-design-config
# 自定义

rm -rf feeds/packages/net/ddns-go
# rm -rf feeds/packages/net/frp
# rm -rf feeds/luci/applications/luci-app-frps
# rm -rf feeds/luci/applications/luci-app-frpc
rm -rf feeds/packages/net/msd_lite
# rm -rf feeds/luci/applications/luci-app-wrtbwmon
# rm -rf feeds/packages/admin/netdata
# rm -rf feeds/luci/applications/luci-app-netdata
# rm -rf feeds/packages/net/qBittorrent
# rm -rf feeds/packages/net/qBittorrent-static
# rm -rf feeds/luci/applications/luci-app-qbittorrent
rm -rf feeds/luci/applications/luci-app-serverchan

# 1 启用 frps
# rm -rf feeds/packages/net/frp
# git clone https://github.com/kuoruan/openwrt-frp feeds/packages/net/frp
# git clone https://github.com/kuoruan/openwrt-frp -b v0.53.2-1 feeds/packages/net/frp
# git clone https://github.com/user1121114685/frp.git feeds/packages/net/frp
# rm -rf feeds/luci/applications/luci-app-frps
# git clone https://github.com/user1121114685/luci-app-frps.git feeds/luci/applications/luci-app-frps

# Default IP
#sed -i 's/192.168.1.1/192.168.6.50/g' package/base-files/files/bin/config_generate

# Set DISTRIB_REVISION
sed -i "s/OpenWrt /Lein Build $(TZ=UTC-8 date "+%Y.%m.%d") @ OpenWrt /g" package/lean/default-settings/files/zzz-default-settings
sed -i 's#mount -t cifs#mount.cifs#g' feeds/luci/applications/luci-app-cifs-mount/root/etc/init.d/cifs
sed -i 's/invalid users = root/#invalid users = root/g' feeds/packages/net/samba4/files/smb.conf.template

# 修改主机名
#sed -i 's/LEDE/OpenWrt/g' package/base-files/files/bin/config_generate
sed -i 's/LEDE/N1/g' package/base-files/luci2/bin/config_generate

# Modify default IP   第一行19.07的路径   第二行23.05的路径
#sed -i 's/192.168.1.1/192.168.123.2/g' package/base-files/files/bin/config_generate
sed -i 's/192.168.1.1/192.168.3.3/g' package/base-files/luci2/bin/config_generate

# golang版本修复
rm -rf feeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang -b 24.x feeds/packages/lang/golang

#修改默认时间格式
sed -i 's/os.date()/os.date("%Y-%m-%d %H:%M:%S %A")/g' $(find ./package/*/autocore/files/ -type f -name "index.htm")
