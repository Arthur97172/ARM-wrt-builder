#!/bin/bash
# 此脚本在 Imagebuilder 根目录运行
ROOTFS_PARTSIZE=${2:-"2048"}    
echo "Target Profile: $PROFILE"
echo "Rootfs Size: $ROOTFS_PARTSIZE MB"
LOGFILE="/tmp/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >> $LOGFILE

# ============================================
# 步骤1: 加载第三方插件配置
# ============================================
CUSTOM_PACKAGES=""
if [ -f "apk-custom-packages.sh" ]; then
    source apk-custom-packages.sh
elif [ -f "custom-packages.sh" ]; then
    source custom-packages.sh
fi

HAS_CUSTOM_PACKAGES="no"
if [ -n "$CUSTOM_PACKAGES" ]; then
    HAS_CUSTOM_PACKAGES="yes"
    echo "✅ 检测到第三方插件: $CUSTOM_PACKAGES"
fi

# 定义所需安装的包列表
PACKAGES=""

# [核心系统 - 不含 libc/libgcc,由 base 系统提供]
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
# 步骤2: 处理第三方插件
# ============================================
THIRD_PARTY_OK=0
if [ "$HAS_CUSTOM_PACKAGES" = "yes" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始处理第三方APK..."

    echo "克隆 OpenWrt-App 仓库..."
    rm -rf /tmp/store-repo
    if git clone --depth=1 https://github.com/Arthur97172/OpenWrt-App.git /tmp/store-repo 2>/tmp/git-clone.log; then
        THIRD_PARTY_OK=1
    else
        echo "⚠️ git clone 失败(继续构建,不含第三方插件):"
        sed 's/^/    /' /tmp/git-clone.log
    fi
fi

if [ "$THIRD_PARTY_OK" = "1" ]; then
    mkdir -p thirdparty apk-merged

    echo "复制第三方 APK 到 thirdparty/ 目录..."
    if [ -d /tmp/store-repo/apk/aarch64_generic ]; then
        find /tmp/store-repo/apk/aarch64_generic -name '*.apk' -exec cp -t apk-merged {} + 2>/dev/null || true
    fi

    if [ -d apk-merged ] && [ -n "$(ls apk-merged/*.apk 2>/dev/null)" ]; then
        cp apk-merged/*.apk thirdparty/ 2>/dev/null
    else
        echo "⚠️ 未在仓库中找到 aarch64*/.apk,跳过第三方"
        THIRD_PARTY_OK=0
    fi

    APK_COUNT=$(find thirdparty -name '*.apk' 2>/dev/null | wc -l)
    echo "✅ 第三方目录现有 $APK_COUNT 个APK文件"
    if [ "$APK_COUNT" -eq 0 ]; then
        echo "⚪️ 未获取到任何第三方 apk,继续构建"
        THIRD_PARTY_OK=0
    fi
fi

if [ "$THIRD_PARTY_OK" = "1" ]; then
    echo "复制第三方 APK 到 imagebuilder/packages/ ..."
    mkdir -p packages

    SKIP_APKS=""
    APK_BIN="staging_dir/host/bin/apk"
    APK_KEYS_DIR="keys"
    APK_SIGN_KEY="$APK_KEYS_DIR/local-private-key.pem"
    if [ ! -s "$APK_SIGN_KEY" ]; then
        APK_SIGN_KEY="$APK_KEYS_DIR/build_key.apk.sec"
    fi

    echo "🔖 重命名 apk 为 canonical 名称(name-version.apk)..."
    canoned=0
    cached=0
    skipped=0
    for f in thirdparty/*.apk; do
        [ -e "$f" ] || continue
        base=$(basename "$f")
        skip=0
        for s in $SKIP_APKS; do
            case "$base" in $s) skip=1 ;; esac
        done
        if [ "$skip" = "1" ]; then
            echo "    ↷ 跳过: $base"
            continue
        fi
        canon_name=$("$APK_BIN" adbdump "$f" 2>/dev/null \
            | awk '/^  name:/ {name=$2} /^  version:/ {ver=$2; print name; print ver}' | head -2)
        canon_pkg=$(echo "$canon_name" | head -1)
        canon_ver=$(echo "$canon_name" | sed -n '2p')
        if [ -z "$canon_pkg" ] || [ -z "$canon_ver" ]; then
            echo "    ⚠️ 无法读 metadata(可能是损坏的 apk):$base — 跳过"
            continue
        fi
        target="$canon_pkg-$canon_ver.apk"
        if [ -f "packages/$target" ] && [ "packages/$target" -nt "$f" ]; then
            cached=$((cached+1))
            continue
        fi
        cp -f "$f" "packages/$target"
        canoned=$((canoned+1))
    done
    echo "📦 重命名 $canoned 新 apk,缓存 $cached 个,跳过 $skipped 个"
    PKG_IN_POOL=$(ls packages/*.apk 2>/dev/null | wc -l)
    echo "✅ 第三方 APK 已合并到 packages/ (池中现共 $PKG_IN_POOL 个文件)"

    OPENSSL_BIN="staging_dir/host/bin/openssl"
    NE_KEY="$APK_KEYS_DIR/local-private-key.pem"
    NEED_KEY_GEN=0
    if [ ! -s "$NE_KEY" ] && [ ! -s "$APK_KEYS_DIR/build_key.apk.sec" ]; then
        NEED_KEY_GEN=1
    fi
    if [ "$NEED_KEY_GEN" = "1" ] && [ -x "$OPENSSL_BIN" ]; then
        echo "🔑 预生成 EC 签名 key(与 IB _check_keys 一致)..."
        mkdir -p "$APK_KEYS_DIR"
        if ! "$OPENSSL_BIN" ecparam -name prime256v1 -genkey -noout -out "$NE_KEY" 2>/dev/null; then
            echo "⚠️ ecparam 生成私钥失败,继续依赖 IB 的 _check_keys"
        else
            sed -i '1s/^/untrusted comment: Local build key\n/' "$NE_KEY" 2>/dev/null
            if "$OPENSSL_BIN" ec -in "$NE_KEY" -pubout > "$APK_KEYS_DIR/local-public-key.pem" 2>/dev/null; then
                sed -i '1s/^/untrusted comment: Local build key\n/' "$APK_KEYS_DIR/local-public-key.pem" 2>/dev/null
                ls -la "$APK_KEYS_DIR/"
                echo "✅ EC key 就绪:$NE_KEY"
            else
                echo "⚠️ 导出公钥失败,继续依赖 IB 的 _check_keys"
            fi
        fi
    fi

    run_mkndx() {
        local args=("$@")
        local cmd=(../"$APK_BIN" mkndx)
        if [ -s "$APK_SIGN_KEY" ]; then
            cmd+=(--keys-dir "$(pwd)/$APK_KEYS_DIR")
            cmd+=(--sign "$(pwd)/$APK_SIGN_KEY")
        fi
        cmd+=(--allow-untrusted --output packages.adb "${args[@]}")
        "${cmd[@]}"
    }

    if [ -x "$APK_BIN" ]; then
        APK_FILES=()
        for f in packages/*.apk; do
            [ -e "$f" ] || continue
            APK_FILES+=("$(basename "$f")")
        done
        PKG_COUNT="${#APK_FILES[@]}"
        echo "🔧 显式重建 SIGNED packages.adb 索引(待索引 apk 数量: $PKG_COUNT)..."
        if [ "$PKG_COUNT" -eq 0 ]; then
            echo "⚠️ packages/ 是空的,没有 apk 可索引,跳过"
        elif (cd packages && run_mkndx "${APK_FILES[@]}"); then
            echo "✅ SIGNED packages.adb 已就绪 ($PKG_COUNT 个 apk)"
        else
            echo "⚠️ mkndx 整体失败,逐个诊断损坏的 apk ..."
            BAD=()
            for entry in "${APK_FILES[@]}"; do
                if ! (cd packages && run_mkndx "$entry"); then
                    echo "    ✗ 损坏: packages/$entry"
                    BAD+=("$entry")
                fi
            done
            if [ "${#BAD[@]}" -gt 0 ]; then
                echo "🚮 暂时移出损坏的 apk ..."
                mkdir -p packages/.bad
                for entry in "${BAD[@]}"; do
                    mv "packages/$entry" "packages/.bad/$entry"
                done
                APK_FILES=()
                for f in packages/*.apk; do
                    [ -e "$f" ] || continue
                    APK_FILES+=("$(basename "$f")")
                done
                if [ "${#APK_FILES[@]}" -eq 0 ]; then
                    echo "⚠️ 没有健康的 apk 留下来,跳过重建"
                elif (cd packages && run_mkndx "${APK_FILES[@]}"); then
                    echo "✅ 已用剩余的健康 apk 重建 SIGNED 索引"
                fi
            fi
        fi

        if [ -f packages/packages.adb ]; then
            touch -d "@$(($(date +%s) + 60))" packages/packages.adb 2>/dev/null || \
                touch packages/packages.adb
            echo "🔒 packages.adb mtime 已更新,IB 不会重建"
        fi
    else
        echo "⚠️ 找不到 $APK_BIN,继续依赖 IB 自动重建(不推荐)"
    fi
fi

# ============================================
# 步骤3: 合并第三方插件到包列表
# ============================================
PACKAGES="$PACKAGES $CUSTOM_PACKAGES"

echo "$(date '+%Y-%m-%d %H:%M:%S') - 编译包列表:"
echo "$PACKAGES"

# ============================================
# 步骤4: 特殊处理 (openclash 等)
# ============================================
if echo "$PACKAGES" | grep -q "luci-app-openclash"; then
    echo "✅ 已选择 luci-app-openclash,添加 openclash core"
    mkdir -p files/etc/openclash/core
    META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-arm64.tar.gz"
    wget -qO- $META_URL | tar xOvz > files/etc/openclash/core/clash_meta
    chmod +x files/etc/openclash/core/clash_meta
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O files/etc/openclash/GeoIP.dat
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O files/etc/openclash/GeoSite.dat
else
    echo "⚪️ 未选择 luci-app-openclash"
fi

# ============================================
# 步骤5: 关闭 apk 签名校验
# ============================================
if [ -f .config ] && grep -q "^CONFIG_SIGNATURE_CHECK=y" .config; then
    cp .config .config.bak.imm
    sed -i 's/^CONFIG_SIGNATURE_CHECK=y$/CONFIG_SIGNATURE_CHECK=/' .config
    echo "🔓 .config: CONFIG_SIGNATURE_CHECK 已置空(原值备份到 .config.bak.imm)"
    grep -n '^CONFIG_SIGNATURE_CHECK' .config
fi

# ============================================
# 步骤 5.1: 修正 APK 数据库与公钥预存路径 [关键修复!]
# ============================================
echo "🛠️ 正在预创建 ImageBuilder 构建工作目录中的 APK 数据库文件夹..."

# 1. 查找或预置所有的 Target Rootfs 构建路径
# ImageBuilder 在运行 make image 时会将临时 Target 安装目录置于 build_dir/target-* 下
TARGET_BUILD_DIRS=$(find build_dir/ -maxdepth 2 -type d -name "root-*" 2>/dev/null)

if [ -z "$TARGET_BUILD_DIRS" ]; then
    # 如果还没有 build_dir，预先按照当前架构创建常规的 root-armsr 路径
    mkdir -p "build_dir/target-aarch64_generic_musl/root-armsr/lib/apk/db"
    mkdir -p "build_dir/target-aarch64_generic_musl/root-armsr/var/lib/apk"
    mkdir -p "build_dir/target-aarch64_generic_musl/root-armsr/etc/apk/keys"
else
    for bdir in $TARGET_BUILD_DIRS; do
        mkdir -p "$bdir/lib/apk/db"
        mkdir -p "$bdir/var/lib/apk"
        mkdir -p "$bdir/etc/apk/keys"
    done
fi

# 2. 正确地将本地签名公钥注入给系统 rootfs (通过 files 目录)
mkdir -p files/etc/apk/keys
if [ -d "keys" ]; then
    cp -vf keys/*.pem files/etc/apk/keys/ 2>/dev/null || true
fi

# 3. 如果在 repositories.conf 同级目录下没有 keys 目录，软链接补全
mkdir -p etc/apk/keys
if [ -d "keys" ]; then
    cp -vf keys/*.pem etc/apk/keys/ 2>/dev/null || true
fi

# ============================================
# 步骤6: 执行 make image
# ============================================
make image PROFILE="$PROFILE" PACKAGES="$PACKAGES" FILES="files" ROOTFS_PARTSIZE="$ROOTFS_PARTSIZE"

if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Build failed!"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Build completed successfully."
