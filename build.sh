#!/bin/bash

# 构建 Claude Code Switcher for macOS
# 使用替代方法绕过 xcodebuild 段错误问题

set -e

echo "开始构建 Claude Code Switcher..."

# 清理之前的构建
echo "清理之前的构建..."
rm -rf build/

# 创建构建目录
mkdir -p build

echo "编译 Swift 源代码..."

# 找到所有 Swift 文件
SWIFT_FILES=$(find ClaudeCodeSwitcher -name "*.swift" | tr '\n' ' ')

# 使用 swiftc 直接编译
swiftc -o build/ClaudeCodeSwitcher \
    -target x86_64-apple-macos12.0 \
    $SWIFT_FILES

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

# 复制资源文件
if [ -d "ClaudeCodeSwitcher/Resources/Assets.xcassets" ]; then
    cp -R ClaudeCodeSwitcher/Resources/Assets.xcassets "$RESOURCES_PATH/"
fi

if [ -f "ClaudeCodeSwitcher/Resources/Info.plist" ]; then
    cp ClaudeCodeSwitcher/Resources/Info.plist "$CONTENTS_PATH/"
fi

# 创建基本的 Info.plist（如果不存在）
if [ ! -f "$CONTENTS_PATH/Info.plist" ]; then
    cat > "$CONTENTS_PATH/Info.plist" << EOF
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
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF
fi

# 使应用可执行
chmod +x "$MACOS_PATH/ClaudeCodeSwitcher"

# 对应用程序进行代码签名
echo "对应用程序进行代码签名..."
codesign --force --deep --sign - "$APP_PATH"

echo "构建完成！"
echo "应用位置: $APP_PATH"

# 创建 DMG（可选）
if command -v create-dmg &> /dev/null; then
    echo "创建 DMG 安装包..."
    create-dmg \
        --volname "Claude Code Switcher" \
        --window-pos 200 120 \
        --window-size 600 300 \
        --icon-size 100 \
        --icon "ClaudeCodeSwitcher.app" 175 120 \
        --hide-extension "ClaudeCodeSwitcher.app" \
        --app-drop-link 425 120 \
        "build/ClaudeCodeSwitcher.dmg" \
        "build/"
fi

echo "构建流程完成！"