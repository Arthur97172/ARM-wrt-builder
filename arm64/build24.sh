#!/bin/bash
# Log file for debugging

# --- 接收外部参数 ---
# $1, $2 是执行脚本时后面跟着的参数
PROFILE=${1:-"friendlyarm_nanopc-t6"}      # 如果没传，默认 r3s
ROOTFS_PARTSIZE=${2:-"1024"}                 # 如果没传，默认 1024
INCLUDE_DOCKER=${INCLUDE_DOCKER:-"no"}       # 通过 env 传入

# 验证收到的参数
echo "Target Profile: $PROFILE"
echo "Rootfs Size: $ROOTFS_PARTSIZE"
echo "Include Docker: $INCLUDE_DOCKER"

source custom-packages.sh
echo "第三方软件包: $CUSTOM_PACKAGES"
LOGFILE="/tmp/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >> $LOGFILE

# yml 传入的路由器型号 PROFILE
echo "Building for profile: $PROFILE"
# yml 传入的固件大小 ROOTFS_PARTSIZE
echo "Building for ROOTFS_PARTSIZE: $ROOTFS_PARTSIZE"

#查询是否包含第三方软件包
if [ -z "$CUSTOM_PACKAGES" ]; then
  echo "⚪️ 未选择 任何第三方软件包"
else
  # ============= 同步第三方插件库==============
  # 同步第三方软件仓库run/ipk
  echo "🔄 正在同步第三方软件仓库 Cloning run file repo..."
  # 增加超时和重试机制
  rm -rf /tmp/store-run-repo 2>/dev/null
  if ! git clone --depth=1 https://github.com/Arthur97172/OpenWrt-App.git /tmp/store-run-repo; then
      echo "❌ git clone 失败！请检查网络或仓库是否可用"
      exit 1
  fi

  # === 验证克隆结果 ===
  echo "✅ git clone 完成，开始验证..."
  if [ ! -d "/tmp/store-run-repo" ]; then
      echo "❌ 仓库目录不存在，克隆失败"
      exit 1
  fi

  echo "📁 仓库目录结构："
  ls -la /tmp/store-run-repo/

  # 拷贝 arm64 下所有 ipk 文件到 extra-packages 目录
  mkdir -p extra-packages
  cp -r /tmp/store-run-repo/ipk/{aarch64_generic,aarch64_cortex-a53}/* extra-packages/ 2>/dev/null || true

  echo "✅ Run files copied to extra-packages:"
  ls -lh extra-packages/*.run
  # 解压并拷贝ipk到packages目录
  sh prepare-packages.sh
  echo "打印imagebuilder/packages目录结构"
  ls -lah packages/ |grep partexp
  # 添加架构优先级信息
  sed -i '1i\
  arch aarch64_generic 10\n\
  arch aarch64_cortex-a53 15' repositories.conf
fi

# 输出调试信息
echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始构建固件..."
echo "查看repositories.conf信息——————"
cat repositories.conf

# 定义所需安装的包列表
PACKAGES=""

# [核心系统]
PACKAGES="base-files libc libgcc uci ubus dropbear logd mtd opkg bash htop curl wget ca-bundle ca-certificates"
PACKAGES="$PACKAGES -dnsmasq dnsmasq-full firewall4 nftables kmod-nft-offload"
PACKAGES="$PACKAGES ip-full ipset iw ppp ppp-mod-pppoe -wpad-basic-mbedtls wpad-openssl"

# [硬件驱动 - 板载 PCIe]
# 强制去重 ath10k 防止冲突；包含 Realtek 板载 2.5G (r8125) 和千兆 (r8169)
PACKAGES="$PACKAGES -kmod-ath10k-sdio kmod-ath10k"
PACKAGES="$PACKAGES kmod-ata-ahci kmod-ata-dwc kmod-mmc kmod-r8125 kmod-r8168 kmod-r8169 r8169-firmware"

# [磁盘与文件系统]
PACKAGES="$PACKAGES block-mount fdisk lsblk blkid parted resize2fs smartmontools"
PACKAGES="$PACKAGES kmod-fs-ext4 kmod-fs-vfat kmod-fs-ntfs3 kmod-fs-exfat kmod-fs-btrfs kmod-fs-f2fs"
PACKAGES="$PACKAGES kmod-usb-storage kmod-usb-storage-uas kmod-usb2 kmod-usb3"

# [增强型 USB 有线网卡驱动 - 支持 100M/1G/2.5G/5G]
# 支持 RTL8152/8153/8156(2.5G)
PACKAGES="$PACKAGES kmod-usb-net kmod-usb-net-rtl8150 kmod-usb-net-rtl8152 r8152-firmware"
# 支持 ASIX AX88179 (主流千兆 USB 网卡)
PACKAGES="$PACKAGES kmod-usb-net-asix-ax88179"
# 支持 Aquantia AQC111 (主流 5G USB 网卡)
PACKAGES="$PACKAGES kmod-usb-net-aqc111"
# 支持 CDC 协议 (手机 USB 共享、5G 随身 WiFi、通用免驱网卡)
PACKAGES="$PACKAGES kmod-usb-net-cdc-ether kmod-usb-net-cdc-ncm kmod-usb-net-cdc-mbim"

# 博通无线网卡核心驱动
PACKAGES="$PACKAGES kmod-brcmfmac"
PACKAGES="$PACKAGES kmod-brcmsmac"
PACKAGES="$PACKAGES brcmfmac-firmware-usb"
PACKAGES="$PACKAGES brcmfmac-firmware-43430-sdio"
PACKAGES="$PACKAGES brcmfmac-firmware-43455-sdio"

#联发科无线网卡核心驱动
PACKAGES="$PACKAGES kmod-usb-ohci"
PACKAGES="$PACKAGES kmod-usb-ohci-pci"
PACKAGES="$PACKAGES kmod-usb-core"
PACKAGES="$PACKAGES kmod-usb2-pci"
PACKAGES="$PACKAGES usbutils"
PACKAGES="$PACKAGES kmod-mac80211"
PACKAGES="$PACKAGES kmod-mt7921-common"
PACKAGES="$PACKAGES kmod-mt7921-firmware"
PACKAGES="$PACKAGES kmod-mt7921e"
PACKAGES="$PACKAGES kmod-mt7921u"
PACKAGES="$PACKAGES kmod-mt7922-firmware"
PACKAGES="$PACKAGES kmod-mt7925-common"
PACKAGES="$PACKAGES kmod-mt7925-firmware"
PACKAGES="$PACKAGES kmod-mt7925e"
PACKAGES="$PACKAGES kmod-mt7925u"
PACKAGES="$PACKAGES kmod-mt792x-common"
PACKAGES="$PACKAGES kmod-mt792x-usb"
PACKAGES="$PACKAGES kmod-mt7992-23-firmware"
PACKAGES="$PACKAGES kmod-mt7992-firmware"
PACKAGES="$PACKAGES kmod-mt7996-233-firmware"
PACKAGES="$PACKAGES kmod-mt7996-firmware"
PACKAGES="$PACKAGES kmod-mt7996-firmware-common"
PACKAGES="$PACKAGES kmod-mt7996e"
PACKAGES="$PACKAGES kmod-mtk-t7xx"

# --- 核心应用界面 ---
PACKAGES="$PACKAGES luci luci-base luci-compat luci-mod-admin-full"
PACKAGES="$PACKAGES luci-app-ttyd"

# LuCI 中文本地化与插件
PACKAGES="$PACKAGES luci-i18n-package-manager-zh-cn"
#PACKAGES="$PACKAGES luci-i18n-filetransfer-zh-cn"
#PACKAGES="$PACKAGES luci-i18n-quickstart-zh-cn"
PACKAGES="$PACKAGES luci-base luci-i18n-base-zh-cn"
PACKAGES="$PACKAGES luci-i18n-firewall-zh-cn"
PACKAGES="$PACKAGES luci-i18n-ttyd-zh-cn"
PACKAGES="$PACKAGES luci-i18n-upnp-zh-cn"
#PACKAGES="$PACKAGES luci-i18n-cifs-mount-zh-cn"
#PACKAGES="$PACKAGES luci-i18n-unishare-zh-cn"
#PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"

# --- 功能插件 (基于你的配置) ---
PACKAGES="$PACKAGES luci-app-samba4 luci-i18n-samba4-zh-cn"
PACKAGES="$PACKAGES luci-app-upnp luci-i18n-upnp-zh-cn"
PACKAGES="$PACKAGES luci-app-wol luci-i18n-wol-zh-cn"
PACKAGES="$PACKAGES luci-app-ddns luci-i18n-ddns-zh-cn"

# ======== shell/custom-packages.sh =======
# 合并imm仓库以外的第三方插件
PACKAGES="$PACKAGES $CUSTOM_PACKAGES"

# [Docker 插件]
if [ "$INCLUDE_DOCKER" = "yes" ]; then
    echo "🐳 Docker enabled, adding docker packages"
    PACKAGES="$PACKAGES docker docker-compose luci-app-dockerman luci-i18n-dockerman-zh-cn"
fi

# 构建镜像
echo "$(date '+%Y-%m-%d %H:%M:%S') - Building image with the following packages:"
echo "$PACKAGES"

# 若构建openclash 则添加内核
if echo "$PACKAGES" | grep -q "luci-app-openclash"; then
    echo "✅ 已选择 luci-app-openclash，添加 openclash core"
    mkdir -p files/etc/openclash/core
    # Download clash_meta
    META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-arm64.tar.gz"
    wget -qO- $META_URL | tar xOvz > files/etc/openclash/core/clash_meta
    chmod +x files/etc/openclash/core/clash_meta
    # Download GeoIP and GeoSite
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O files/etc/openclash/GeoIP.dat
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O files/etc/openclash/GeoSite.dat
else
    echo "⚪️ 未选择 luci-app-openclash"
fi


#make image PROFILE=$PROFILE PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files" ROOTFS_PARTSIZE=$ROOTFS_PARTSIZE
make image PROFILE="$PROFILE" PACKAGES="$PACKAGES" FILES="files" CONFIG_TARGET_ROOTFS_PARTSIZE="$ROOTFS_PARTSIZE"

if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Build failed!"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Build completed successfully."
