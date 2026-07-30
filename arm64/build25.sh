#!/bin/bash
# Wrt 25.12.x armv8 构建脚本 (APK 架构稳定修复版)
# 在 imagebuilder 目录下运行

set -e # 遇到错误即刻停止

# --- 接收外部参数 ---
ROOTFS_PARTSIZE=${2:-"2048"}
INCLUDE_DOCKER=${INCLUDE_DOCKER:-"no"}

echo "Target Profile: ${PROFILE:-generic}"
echo "Rootfs Size: $ROOTFS_PARTSIZE MB"
echo "Include Docker: $INCLUDE_DOCKER"

# ============================================
# 步骤1: 加载第三方插件配置
# ============================================
CUSTOM_PACKAGES=""
if [ -f "apk-custom-packages.sh" ]; then
    source apk-custom-packages.sh
fi

HAS_CUSTOM_PACKAGES="no"
if [ -n "$CUSTOM_PACKAGES" ]; then
    HAS_CUSTOM_PACKAGES="yes"
    echo "✅ 检测到第三方插件: $CUSTOM_PACKAGES"
fi

# 定义所需安装的包列表
PACKAGES=""

# [核心系统]
PACKAGES="$PACKAGES base-files uci ubus dropbear logd mtd bash htop curl wget ca-bundle ca-certificates"
PACKAGES="$PACKAGES dnsmasq-full firewall4 nftables kmod-nft-offload"
PACKAGES="$PACKAGES ip-full ipset iw ppp ppp-mod-pppoe -wpad-basic-mbedtls wpad-openssl libustream-openssl"

# [硬件驱动]
PACKAGES="$PACKAGES -kmod-ath10k-sdio kmod-ath10k"
PACKAGES="$PACKAGES kmod-ata-ahci kmod-ata-ahci-dwc kmod-mmc kmod-r8125 kmod-r8168 kmod-r8169 r8169-firmware"

# [磁盘与文件系统]
PACKAGES="$PACKAGES block-mount fdisk lsblk blkid parted resize2fs smartmontools"
PACKAGES="$PACKAGES kmod-fs-ext4 kmod-fs-vfat kmod-fs-ntfs3 kmod-fs-exfat kmod-fs-btrfs kmod-fs-f2fs"
PACKAGES="$PACKAGES kmod-usb-storage kmod-usb-storage-uas kmod-usb2 kmod-usb3"

# [USB 网卡驱动]
PACKAGES="$PACKAGES kmod-usb-net kmod-usb-net-rtl8150 kmod-usb-net-rtl8152 r8152-firmware"
PACKAGES="$PACKAGES kmod-usb-net-asix-ax88179 kmod-usb-net-aqc111"
PACKAGES="$PACKAGES kmod-usb-net-cdc-ether kmod-usb-net-cdc-ncm kmod-usb-net-cdc-mbim"

# [无线驱动]
PACKAGES="$PACKAGES kmod-brcmfmac kmod-brcmsmac"
PACKAGES="$PACKAGES brcmfmac-firmware-usb brcmfmac-firmware-43430-sdio brcmfmac-firmware-43455-sdio"
PACKAGES="$PACKAGES kmod-usb-ohci kmod-usb-ohci-pci kmod-usb-core kmod-usb2-pci usbutils"
PACKAGES="$PACKAGES kmod-mac80211"
PACKAGES="$PACKAGES kmod-mt7921-common kmod-mt7921-firmware kmod-mt7921e kmod-mt7921u"
PACKAGES="$PACKAGES kmod-mt7922-firmware kmod-mt7925-common kmod-mt7925-firmware kmod-mt7925e kmod-mt7925u"
PACKAGES="$PACKAGES kmod-mt792x-common kmod-mt792x-usb"
PACKAGES="$PACKAGES kmod-mt7992-23-firmware kmod-mt7992-firmware"
PACKAGES="$PACKAGES kmod-mt7996-233-firmware kmod-mt7996-firmware kmod-mt7996-firmware-common kmod-mt7996e kmod-mtk-t7xx"

# [Web 界面]
PACKAGES="$PACKAGES luci luci-base luci-i18n-base-zh-cn luci-mod-admin-full"
PACKAGES="$PACKAGES luci-app-ttyd luci-i18n-ttyd-zh-cn"

# [功能插件]
PACKAGES="$PACKAGES luci-app-samba4 luci-i18n-samba4-zh-cn"
PACKAGES="$PACKAGES luci-app-upnp luci-i18n-upnp-zh-cn"
PACKAGES="$PACKAGES luci-app-wol luci-i18n-wol-zh-cn"
PACKAGES="$PACKAGES luci-app-ddns luci-i18n-ddns-zh-cn"
PACKAGES="$PACKAGES luci-app-package-manager luci-i18n-package-manager-zh-cn"

# Docker 插件
if [ "$INCLUDE_DOCKER" = "yes" ]; then
    echo "🐳 Docker enabled, adding docker packages"
    PACKAGES="$PACKAGES docker docker-compose luci-app-dockerman luci-i18n-dockerman-zh-cn"
fi

# ============================================
# 步骤2: 处理第三方插件与生成 APK 索引
# ============================================
THIRD_PARTY_OK=0
if [ "$HAS_CUSTOM_PACKAGES" = "yes" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始处理第三方APK..."
    rm -rf /tmp/store-repo
    if git clone --depth=1 https://github.com/Arthur97172/OpenWrt-App.git /tmp/store-repo 2>/tmp/git-clone.log; then
        THIRD_PARTY_OK=1
    else
        echo "⚠️ git clone 失败(继续构建,不含第三方插件):"
        sed 's/^/    /' /tmp/git-clone.log
    fi
fi

if [ "$THIRD_PARTY_OK" = "1" ]; then
    mkdir -p packages

    if [ -d /tmp/store-repo/apk/aarch64_generic ]; then
        find /tmp/store-repo/apk/aarch64_generic -name '*.apk' -exec cp -t packages/ {} + 2>/dev/null || true
    fi

    PKG_COUNT=$(find packages -name '*.apk' 2>/dev/null | wc -l)
    echo "✅ packages/ 目录下现共有 $PKG_COUNT 个第三方 APK 文件"

    # 如果存在本地包，生成本地 APK 索引文件并写入 repositories 配置文件
    if [ $PKG_COUNT -gt 0 ]; then
        echo "📦 正在生成本地 packages.adb 索引..."
        if command -v apk >/dev/null 2>&1; then
            apk mkndx --output packages/packages.adb packages/*.apk 2>/dev/null || true
        elif [ -f "./staging_dir/host/bin/apk" ]; then
            ./staging_dir/host/bin/apk mkndx --output packages/packages.adb packages/*.apk 2>/dev/null || true
        fi

        LOCAL_REPO_PATH="$(pwd)/packages/packages.adb"
        if [ -f repositories ]; then
            echo "$LOCAL_REPO_PATH" >> repositories
            echo "✅ 已向 repositories 追加本地源路径: $LOCAL_REPO_PATH"
        fi
    fi
fi

# ============================================
# 步骤3: 合并第三方插件到包列表
# ============================================
PACKAGES="$PACKAGES $CUSTOM_PACKAGES"

echo "$(date '+%Y-%m-%d %H:%M:%S') - 编译包列表:"
echo "$PACKAGES"

# ============================================
# 步骤4: 特殊处理 (OpenClash 等)
# ============================================
if echo "$PACKAGES" | grep -q "luci-app-openclash"; then
    echo "✅ 已选择 luci-app-openclash,添加 openclash core"
    mkdir -p files/etc/openclash/core
    META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-arm64.tar.gz"
    wget -qO- $META_URL | tar xOvz > files/etc/openclash/core/clash_meta 2>/dev/null || true
    chmod +x files/etc/openclash/core/clash_meta 2>/dev/null || true
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O files/etc/openclash/GeoIP.dat 2>/dev/null || true
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O files/etc/openclash/GeoSite.dat 2>/dev/null || true
fi

# ============================================
# 步骤5: 安全修改 Makefile (防止损坏语法，只做轻量参数替换)
# ============================================
if [ -f Makefile ]; then
    # 替换其中的默认签名检查开关，加上未信任签名放行参数
    sed -i 's/--keys-dir/--allow-untrusted --keys-dir/g' Makefile 2>/dev/null || true
fi

# ============================================
# 步骤6: 执行 make image
# ============================================
ROOTFS_PARTSIZE=${ROOTFS_PARTSIZE:-"2048"}
PROFILE_NAME=${PROFILE:-"generic"}

make image PROFILE="$PROFILE_NAME" \
           PACKAGES="$PACKAGES" \
           FILES="files" \
           ROOTFS_PARTSIZE="$ROOTFS_PARTSIZE" \
           OPTION_ALLOW_UNTRUSTED=1 \
           APK_ARGS="--allow-untrusted"

if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Build failed!"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Build completed successfully."
