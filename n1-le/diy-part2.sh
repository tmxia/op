# Modify some code adaptation
#sed -i 's/LUCI_DEPENDS.*/LUCI_DEPENDS:=\@\(arm\|\|aarch64\)/g' package/lean/luci-app-cpufreq/Makefile
# Add autocore support for armvirt
sed -i 's/TARGET_rockchip/TARGET_rockchip\|\|TARGET_armvirt/g' package/lean/autocore/Makefile

# Modify default IP
sed -i 's/192.168.1.1/192.168.3.3/g' package/base-files/files/bin/config_generate

# => dockerman
git clone https://github.com/lisaac/luci-app-dockerman.git package/luci-app-dockerman

# => passwall
git clone https://github.com/xiaorouji/openwrt-passwall-packages.git -b main package/passwall_package
git clone https://github.com/xiaorouji/openwrt-passwall.git package/passwall

# => passwall2
#git clone https://github.com/xiaorouji/openwrt-passwall-packages.git -b main package/passwall_package
#git clone https://github.com/xiaorouji/openwrt-passwall2.git package/passwall2

# => ssr plus
#git clone --depth=1 https://github.com/fw876/helloworld.git package/helloworld

# => OpenClash
#git clone --depth=1 https://github.com/vernesong/OpenClash.git package/OpenClash

# => mosdns
git clone --depth=1 https://github.com/sbwml/luci-app-mosdns -b v5 package/mosdns

# => 删除默认argon主题
rm -rf feeds/luci/themes/luci-theme-argon

#主题
git clone -b 18.06 https://github.com/jerrykuku/luci-theme-argon package/luci-theme-argon
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' ./feeds/luci/collections/luci/Makefile
