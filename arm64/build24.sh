#!/bin/bash
# 此脚本在Imagebuilder 根目录运行
ROOTFS_PARTSIZE=${2:-"2048"}   
echo "Rootfs Size: $ROOTFS_PARTSIZE"
source custom-packages.sh
echo "第三方软件包: $CUSTOM_PACKAGES"
LOGFILE="/tmp/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >> $LOGFILE

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
PACKAGES="$PACKAGES -dnsmasq dnsmasq-full firewall4 nftables kmod-nft-offload nano"
PACKAGES="$PACKAGES -odhcpd odhcpd-ipv6only"
PACKAGES="$PACKAGES -libustream-mbedtls -libustream-wolfssl libustream-openssl"
PACKAGES="$PACKAGES ip-full ipset iw ppp ppp-mod-pppoe -wpad-basic-mbedtls -wpad-mbedtls -wpad-openssl wpad-mesh-openssl luci-proto-ppp luci-proto-ipv6"
PACKAGES="$PACKAGES kmod-tcp-bbr"

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

# ============================================
# [Docker 插件]
if [ "$INCLUDE_DOCKER" = "yes" ]; then
    echo "🐳 Docker enabled, adding docker packages"
    PACKAGES="$PACKAGES docker docker-compose luci-app-dockerman luci-i18n-dockerman-zh-cn"
fi

# 若构建openclash 则添加内核
if echo "$PACKAGES" | grep -q "luci-app-openclash"; then
    echo "✅ 已选择 luci-app-openclash，添加 openclash core"
    mkdir -p files/etc/openclash/core
    # Download clash_meta
    META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-arm64.tar.gz"
    wget -qO- $META_URL | tar xOvz > files/etc/openclash/core/clash_meta
    chmod +x files/etc/openclash/core/clash_meta
    # 下载 GeoIP and GeoSite 数据库
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O files/etc/openclash/GeoIP.dat
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O files/etc/openclash/GeoSite.dat
    echo "✅ openclash预装GeoData 数据库完成！"
else
    echo "⚪️ 未选择 luci-app-openclash"
fi

# 若构建nikki 则添加GeoIP and GeoSite
if echo "$PACKAGES" | grep -q "luci-app-nikki"; then
    # 创建目录
    mkdir -p files/etc/nikki/run/
    # 下载 GeoIP and GeoSite 数据库
    wget -q https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat -O files/etc/nikki/run/geoip.dat
    wget -q https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat -O files/etc/nikki/run/geosite.dat
    wget -q https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/country.mmdb -O files/etc/nikki/run/country.mmdb
    wget -q https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/GeoLite2-ASN.mmdb -O files/etc/nikki/run/GeoLite2-ASN.mmdb
    #chmod 755 files/etc/nikki/run/*
    # 下载 Zashboard
    wget -q https://github.com/Zephyruso/zashboard/releases/latest/download/dist.zip -O /tmp/dist.zip
    # 解压 Zashboard
    rm -rf files/etc/nikki/run/ui/*
    mkdir -p files/etc/nikki/run/ui
    # 解压 Zashboard到临时文件夹
    unzip -qo /tmp/dist.zip -d /tmp/zashboard
    # 将 dist 目录中的所有内容复制到 Nikki UI 目录
    cp -a /tmp/zashboard/dist/. files/etc/nikki/run/ui/
    # 删除临时文件
    rm -rf /tmp/zashboard
    rm -f /tmp/dist.zip
    # 设置目录和文件权限
    find files/etc/nikki/run -type d -exec chmod 755 {} \;
    find files/etc/nikki/run -type f -exec chmod 644 {} \;
    echo "✅ Nikki 预装 GeoData + Zashboard 完成！"
else
    echo "⚪️ 未选择 luci-app-nikki"
fi


# 若构建 luci-app-netspeedtest，则自动预装最新稳定版 Ookla Speedtest CLI
if echo "$PACKAGES" | grep -q "luci-app-netspeedtest"; then
    echo "🚀 检测到 luci-app-netspeedtest，开始下载最新稳定版 Ookla Speedtest CLI..."
    # 创建目标目录
    mkdir -p files/usr/libexec/netspeedtest
    OOKLA_ARCH="aarch64"
    # 创建临时目录
    rm -rf /tmp/ookla-speedtest
    mkdir -p /tmp/ookla-speedtest
    # ------------------------------------------------------------
    # 从 Ookla 官方 CLI 页面获取最新稳定版 aarch64 下载地址
    # ------------------------------------------------------------
    OOKLA_URL=$(wget -qO- --no-check-certificate \
        "https://www.speedtest.net/apps/cli" \
        | sed -n '/Download for Linux/,/<\/div>/p' \
        | sed -En "s|.*<a href=\"([^\"]+)\"[^>]*>${OOKLA_ARCH}</a>.*|\1|p" \
        | head -n 1)
    # 如果没有找到 URL，尝试兼容其他 HTML 格式
    if [ -z "$OOKLA_URL" ]; then
        OOKLA_URL=$(wget -qO- --no-check-certificate \
            "https://www.speedtest.net/apps/cli" \
            | grep -oE 'https?://[^"]+linux-aarch64[^"]+\.tgz' \
            | head -n 1)
    fi
    # 检查下载地址
    if [ -z "$OOKLA_URL" ]; then
        echo "❌ 无法从 Ookla 官方页面获取最新稳定版 aarch64 下载地址！"
        rm -rf /tmp/ookla-speedtest
        exit 1
    fi
    # 如果官方页面返回相对路径，则补充官方域名
    case "$OOKLA_URL" in
        http://*|https://*)
            ;;
        /*)
            OOKLA_URL="https://www.speedtest.net${OOKLA_URL}"
            ;;
        *)
            OOKLA_URL="https://www.speedtest.net/${OOKLA_URL}"
            ;;
    esac
    echo "🎯 Ookla ARCH: ${OOKLA_ARCH}"
    echo "🔗 Download: ${OOKLA_URL}"
    # ------------------------------------------------------------
    # 下载 Ookla Speedtest CLI（加入最多重试 5 次机制）
    # ------------------------------------------------------------
    MAX_RETRIES=5
    RETRY_COUNT=0
    DOWNLOAD_SUCCESS=0

    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        RETRY_COUNT=$((RETRY_COUNT + 1))
        echo "📥 正在下载 (尝试 $RETRY_COUNT/$MAX_RETRIES)..."
        
        wget -q --no-check-certificate \
            "$OOKLA_URL" \
            -O /tmp/ookla-speedtest/ookla-speedtest.tgz

        # 检查下载文件是否成功且非空
        if [ -s /tmp/ookla-speedtest/ookla-speedtest.tgz ]; then
            DOWNLOAD_SUCCESS=1
            break
        else
            echo "⚠️ 第 $RETRY_COUNT 次下载失败，等待 5 秒后重试..."
            rm -f /tmp/ookla-speedtest/ookla-speedtest.tgz
            sleep 5
        fi
    done

    # 检查最终下载结果
    if [ $DOWNLOAD_SUCCESS -eq 0 ]; then
        echo "❌ Ookla Speedtest CLI 下载失败，已重试 $MAX_RETRIES 次，终止构建！"
        echo "URL: ${OOKLA_URL}"
        rm -rf /tmp/ookla-speedtest
        exit 1
    fi

    echo "📦 Ookla Speedtest CLI 下载完成："
    ls -lh /tmp/ookla-speedtest/ookla-speedtest.tgz
    # ------------------------------------------------------------
    # 解压
    # ------------------------------------------------------------
    tar -xzf \
        /tmp/ookla-speedtest/ookla-speedtest.tgz \
        -C /tmp/ookla-speedtest
    # 检查 speedtest 二进制
    if [ ! -f /tmp/ookla-speedtest/speedtest ]; then
        echo "❌ 解压后未找到 speedtest 二进制文件！"
        rm -rf /tmp/ookla-speedtest
        exit 1
    fi
    chmod 755 /tmp/ookla-speedtest/speedtest
    echo "🔍 检查 Ookla Speedtest CLI 文件..."
    if command -v file >/dev/null 2>&1; then
        file /tmp/ookla-speedtest/speedtest
    fi
    # 使用 readelf 检查 ELF Machine
    if command -v readelf >/dev/null 2>&1; then
        if ! readelf -h /tmp/ookla-speedtest/speedtest | grep -q "AArch64"; then
            echo "❌ Ookla Speedtest CLI 不是 AArch64 ELF 文件！"
            readelf -h /tmp/ookla-speedtest/speedtest
            rm -rf /tmp/ookla-speedtest
            exit 1
        fi
        echo "✅ 已确认 Ookla Speedtest CLI 为 AArch64 架构"
    fi
    # ------------------------------------------------------------
    # 安装到 luci-app-netspeedtest 实际使用的路径
    # ------------------------------------------------------------
    cp -f \
        /tmp/ookla-speedtest/speedtest \
        files/usr/libexec/netspeedtest/speedtest
    chmod 755 \
        files/usr/libexec/netspeedtest/speedtest
    # 检查最终文件
    if [ ! -x files/usr/libexec/netspeedtest/speedtest ]; then
        echo "❌ Ookla Speedtest CLI 安装失败！"
        rm -rf /tmp/ookla-speedtest
        exit 1
    fi
    echo "✅ 最新稳定版 Ookla Speedtest CLI 预装完成！"
    echo "   ARCH : ${OOKLA_ARCH}"
    echo "   PATH : files/usr/libexec/netspeedtest/speedtest"
    if command -v file >/dev/null 2>&1; then
        file files/usr/libexec/netspeedtest/speedtest
    fi
    # 清理临时文件
    rm -rf /tmp/ookla-speedtest
else
    echo "⚪️ 未选择 luci-app-netspeedtest"
fi

# 构建镜像
echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始构建......打印所有包名"
echo "$PACKAGES"

#make image PROFILE=$PROFILE PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files" ROOTFS_PARTSIZE=$ROOTFS_PARTSIZE
ROOTFS_PARTSIZE=${ROOTFS_PARTSIZE:-"2048"}
make image PROFILE=generic PACKAGES="$PACKAGES" FILES="files" ROOTFS_PARTSIZE=$ROOTFS_PARTSIZE

if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Build failed!"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Build completed successfully."
