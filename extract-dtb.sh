#!/bin/bash
set -e

# 获取工作流传入的源仓库简称 (naoki66 或 SongOfLightAndShadow)
PREFIX=$1

if [ -z "$PREFIX" ]; then
    PREFIX="unknown"
fi

echo "=== 开始从下载的 ITB 固件提取 DTB 文件 (来源: $PREFIX) ==="

OUTPUT_DIR="./output"
mkdir -p "$OUTPUT_DIR"

ITB_FILE="firmware-sysupgrade.itb"

if [ ! -f "$ITB_FILE" ]; then
    echo "❌ 错误: 未找到下载的固件文件 $ITB_FILE！"
    exit 1
fi

echo "🔍 正在分析固件内部结构..."
dumpimage -l "$ITB_FILE" || true
echo "----------------------------------------"

echo "🔄 正在扫描并提取所有的 FDT 设备树组件..."

for p in {0..10}; do
    TEMP_BIN="$OUTPUT_DIR/temp_component_$p.bin"
    
    if dumpimage -T flat_dt -p "$p" -o "$TEMP_BIN" "$ITB_FILE" 2>/dev/null; then
        if [ -f "$TEMP_BIN" ]; then
            MAGIC=$(hexdump -n 4 -e '"%08x"' "$TEMP_BIN" 2>/dev/null)
            
            if [ "$MAGIC" == "d00dfeed" ] || [ "$MAGIC" == "edfe0dd0" ]; then
                # 在输出的文件名最前面加上来源前缀，避免重名冲突
                DTB_NAME="${PREFIX}_gemtek-xr1710g-pos$p.dtb"
                
                mv "$TEMP_BIN" "$OUTPUT_DIR/$DTB_NAME"
                echo "✅ [索引 $p] 成功提取到设备树二进制: $DTB_NAME"
            else
                rm -f "$TEMP_BIN"
            fi
        fi
    fi
done

echo "----------------------------------------"
if [ -n "$(ls $OUTPUT_DIR/*.dtb 2>/dev/null)" ]; then
    echo "🎉 提取任务圆满完成！已准备好上传至 Releases。"
    ls -lh "$OUTPUT_DIR"
else
    echo "❌ 未能在该 ITB 固件中定位到有效的 DTB 设备树节点。"
    exit 1
fi
