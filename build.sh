#!/bin/bash

# 构建 Claude Code Switcher for macOS

set -e

echo "开始构建 Claude Code Switcher..."

# 检测系统架构
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    TARGET="arm64-apple-macos12.0"
else
    TARGET="x86_64-apple-macos12.0"
fi
echo "目标架构: $TARGET"

# 方法1: 优先使用 xcodebuild（如果 Xcode 项目可用）
if [ -f "ClaudeCodeSwitcher.xcodeproj/project.pbxproj" ]; then
    echo "使用 xcodebuild 构建..."
    
    # 清理之前的构建
    echo "清理之前的构建..."
    rm -rf build/
    xcodebuild clean -project ClaudeCodeSwitcher.xcodeproj -configuration Release 2>/dev/null || true
    
    # 构建项目
    xcodebuild -project ClaudeCodeSwitcher.xcodeproj \
               -scheme ClaudeCodeSwitcher \
               -configuration Release \
               -derivedDataPath build/DerivedData \
               CONFIGURATION_BUILD_DIR=$(pwd)/build \
               build
    
    if [ $? -eq 0 ]; then
        echo "构建成功！"
        echo "应用位置: build/ClaudeCodeSwitcher.app"
        echo ""
        echo "要启动应用，请运行："
        echo "  open build/ClaudeCodeSwitcher.app"
        exit 0
    else
        echo "xcodebuild 失败，尝试备用方法..."
    fi
fi

# 方法2: 使用 swiftc 直接编译
echo "使用 swiftc 直接编译..."

# 清理之前的构建
echo "清理之前的构建..."
rm -rf build/

# 创建构建目录
mkdir -p build

# 收集所有 Swift 文件
SWIFT_FILES=$(find ClaudeCodeSwitcher -name "*.swift" | tr '\n' ' ')

if [ -z "$SWIFT_FILES" ]; then
    echo "错误：没有找到 Swift 源文件"
    exit 1
fi

echo "编译 Swift 源代码..."

# 直接使用 swiftc 编译
swiftc -o build/ClaudeCodeSwitcher \
       -target $TARGET \
       -framework AppKit \
       -framework SwiftUI \
       -framework Combine \
       -framework Foundation \
       -parse-as-library \
       $SWIFT_FILES

if [ $? -ne 0 ]; then
    echo "编译失败"
    exit 1
fi

echo "创建应用程序包..."

# 创建 app 包结构
APP_NAME="ClaudeCodeSwitcher.app"
APP_PATH="build/$APP_NAME"
CONTENTS_PATH="$APP_PATH/Contents"
MACOS_PATH="$CONTENTS_PATH/MacOS"
RESOURCES_PATH="$CONTENTS_PATH/Resources"

mkdir -p "$MACOS_PATH"
mkdir -p "$RESOURCES_PATH"

# 复制可执行文件
cp build/ClaudeCodeSwitcher "$MACOS_PATH/"

# 复制 Info.plist
if [ -f "ClaudeCodeSwitcher/Resources/Info.plist" ]; then
    cp "ClaudeCodeSwitcher/Resources/Info.plist" "$CONTENTS_PATH/"
else
    # 创建基本的 Info.plist
    cat > "$CONTENTS_PATH/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ClaudeCodeSwitcher</string>
    <key>CFBundleIdentifier</key>
    <string>com.example.claudecodeswitcher</string>
    <key>CFBundleName</key>
    <string>Claude Code Switcher</string>
    <key>CFBundleDisplayName</key>
    <string>Claude Code Switcher</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST
fi

# 复制资源文件
if [ -d "ClaudeCodeSwitcher/Resources/Assets.xcassets" ]; then
    cp -R "ClaudeCodeSwitcher/Resources/Assets.xcassets" "$RESOURCES_PATH/"
fi

# 使应用可执行
chmod +x "$MACOS_PATH/ClaudeCodeSwitcher"

# 对应用程序进行代码签名（使用本地签名）
echo "对应用程序进行代码签名..."
codesign --force --deep --sign - "$APP_PATH"

# 清除扩展属性
echo "清除扩展属性..."
xattr -cr "$APP_PATH" 2>/dev/null || true

# 验证应用
echo "验证应用程序..."
codesign --verify --verbose "$APP_PATH" || true

echo "构建完成！"
echo "应用位置: $APP_PATH"
echo ""
echo "要启动应用，请运行："
echo "  open $APP_PATH"
echo ""
echo "如果仍然提示应用损坏，请在系统设置中："
echo "  1. 打开'隐私与安全性'"
echo "  2. 在'安全性'部分允许运行此应用"
echo "  或者运行: sudo xattr -cr $APP_PATH"