#!/bin/bash

# 生成macOS应用所需的所有图标尺寸
# 使用方法: ./generate_icons.sh input.png

if [ "$#" -ne 1 ]; then
    echo "使用方法: $0 <input_image.png>"
    exit 1
fi

INPUT_IMAGE="$1"
OUTPUT_DIR="ClaudeCodeSwitcher/Resources/Assets.xcassets/AppIcon.appiconset"

# 检查输入文件是否存在
if [ ! -f "$INPUT_IMAGE" ]; then
    echo "错误: 文件 '$INPUT_IMAGE' 不存在"
    exit 1
fi

# 检查是否安装了sips（macOS自带）
if ! command -v sips &> /dev/null; then
    echo "错误: 需要sips命令（macOS自带）"
    exit 1
fi

# 创建输出目录
mkdir -p "$OUTPUT_DIR"

echo "开始生成图标..."

# 生成各种尺寸的图标
# 16x16
sips -z 16 16 "$INPUT_IMAGE" --out "$OUTPUT_DIR/icon_16x16.png" > /dev/null 2>&1
sips -z 32 32 "$INPUT_IMAGE" --out "$OUTPUT_DIR/icon_16x16@2x.png" > /dev/null 2>&1

# 32x32
sips -z 32 32 "$INPUT_IMAGE" --out "$OUTPUT_DIR/icon_32x32.png" > /dev/null 2>&1
sips -z 64 64 "$INPUT_IMAGE" --out "$OUTPUT_DIR/icon_32x32@2x.png" > /dev/null 2>&1

# 128x128
sips -z 128 128 "$INPUT_IMAGE" --out "$OUTPUT_DIR/icon_128x128.png" > /dev/null 2>&1
sips -z 256 256 "$INPUT_IMAGE" --out "$OUTPUT_DIR/icon_128x128@2x.png" > /dev/null 2>&1

# 256x256
sips -z 256 256 "$INPUT_IMAGE" --out "$OUTPUT_DIR/icon_256x256.png" > /dev/null 2>&1
sips -z 512 512 "$INPUT_IMAGE" --out "$OUTPUT_DIR/icon_256x256@2x.png" > /dev/null 2>&1

# 512x512
sips -z 512 512 "$INPUT_IMAGE" --out "$OUTPUT_DIR/icon_512x512.png" > /dev/null 2>&1
sips -z 1024 1024 "$INPUT_IMAGE" --out "$OUTPUT_DIR/icon_512x512@2x.png" > /dev/null 2>&1

echo "✅ 图标生成完成！"
echo "生成的图标位于: $OUTPUT_DIR"

# 列出生成的文件
echo ""
echo "生成的文件列表:"
ls -la "$OUTPUT_DIR"/*.png 2>/dev/null | awk '{print "  - " $NF}'