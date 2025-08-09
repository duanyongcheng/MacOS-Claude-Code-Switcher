#!/bin/bash

# 构建多架构版本的 Claude Code Switcher

set -e

echo "Claude Code Switcher 多架构构建脚本"
echo "====================================="
echo ""

# 默认构建所有版本
BUILD_ALL=true

# 解析参数
if [ "$1" = "universal" ]; then
    BUILD_ALL=false
    echo "仅构建通用版本..."
    ./build.sh --universal
elif [ "$1" = "intel" ]; then
    BUILD_ALL=false
    echo "仅构建 Intel 版本..."
    ./build.sh --intel
elif [ "$1" = "arm" ]; then
    BUILD_ALL=false
    echo "仅构建 Apple Silicon 版本..."
    ./build.sh --arm
else
    # 构建所有版本
    echo "构建所有版本..."
    echo ""
    
    echo "1. 构建通用二进制版本 (Intel + Apple Silicon)..."
    echo "-------------------------------------------------"
    ./build.sh --universal
    
    # 备份通用版本
    if [ -d "build/ClaudeCodeSwitcher.app" ]; then
        cp -R build/ClaudeCodeSwitcher.app build/ClaudeCodeSwitcher-Universal.app
        echo "✓ 通用版本已保存为: build/ClaudeCodeSwitcher-Universal.app"
    fi
    
    echo ""
    echo "2. 构建 Intel 专用版本..."
    echo "--------------------------"
    ./build.sh --intel
    echo "✓ Intel 版本已保存为: build/ClaudeCodeSwitcher-Intel.app"
    
    echo ""
    echo "3. 构建 Apple Silicon 专用版本..."
    echo "-----------------------------------"
    ./build.sh --arm
    echo "✓ Apple Silicon 版本已保存为: build/ClaudeCodeSwitcher-AppleSilicon.app"
fi

echo ""
echo "构建完成！"
echo ""
echo "可用的应用版本："
echo "----------------"
if [ -d "build/ClaudeCodeSwitcher-Universal.app" ] || [ -d "build/ClaudeCodeSwitcher.app" ]; then
    echo "• 通用版本 (推荐): build/ClaudeCodeSwitcher-Universal.app 或 build/ClaudeCodeSwitcher.app"
    echo "  支持: Intel 和 Apple Silicon Mac"
fi
if [ -d "build/ClaudeCodeSwitcher-Intel.app" ]; then
    echo "• Intel 版本: build/ClaudeCodeSwitcher-Intel.app"
    echo "  支持: 仅 Intel Mac"
fi
if [ -d "build/ClaudeCodeSwitcher-AppleSilicon.app" ]; then
    echo "• Apple Silicon 版本: build/ClaudeCodeSwitcher-AppleSilicon.app"
    echo "  支持: 仅 M1/M2/M3 Mac"
fi

echo ""
echo "使用说明："
echo "----------"
echo "1. 通用版本可在所有 Mac 上运行（推荐）"
echo "2. 专用版本体积更小，但只能在对应架构上运行"
echo "3. 双击 .app 文件即可启动应用"
echo ""
echo "如果遇到 '应用已损坏' 提示："
echo "  sudo xattr -cr build/*.app"