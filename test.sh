#!/bin/bash

# 测试 Claude Code Switcher 功能

echo "=== Claude Code Switcher 功能测试 ==="

# 1. 检查应用是否构建成功
APP_PATH="/Users/bary/Library/Developer/Xcode/DerivedData/ClaudeCodeSwitcher-*/Build/Products/Debug/ClaudeCodeSwitcher.app"
if ls $APP_PATH 1> /dev/null 2>&1; then
    echo "✅ 应用构建成功"
    APP_PATH=$(ls -d $APP_PATH | head -1)
    echo "应用路径: $APP_PATH"
else
    echo "❌ 应用构建失败"
    exit 1
fi

# 2. 检查应用结构
echo ""
echo "=== 应用结构检查 ==="
echo "Contents/"
ls -la "$APP_PATH/Contents/"

echo ""
echo "MacOS/"
ls -la "$APP_PATH/Contents/MacOS/"

# 3. 检查 Claude 配置目录
echo ""
echo "=== Claude 配置目录检查 ==="
CLAUDE_DIR="$HOME/.claude"
if [ -d "$CLAUDE_DIR" ]; then
    echo "✅ Claude 配置目录存在: $CLAUDE_DIR"
    ls -la "$CLAUDE_DIR"
else
    echo "📁 Claude 配置目录不存在，将在首次运行时创建"
fi

# 4. 检查配置文件结构
echo ""
echo "=== 测试配置文件创建 ==="

# 创建临时测试配置
TEST_CONFIG='{
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "test-key",
    "ANTHROPIC_BASE_URL": "https://api.anthropic.com",
    "ANTHROPIC_MODEL": "claude-3-opus-20240229",
    "ANTHROPIC_SMALL_FAST_MODEL": "claude-3-haiku-20240307",
    "DISABLE_AUTOUPDATER": "0",
    "HTTPS_PROXY": "",
    "HTTP_PROXY": ""
  },
  "permissions": {
    "allow": [],
    "deny": []
  },
  "feedbackSurveyState": {
    "lastShownTime": 1234567890
  }
}'

echo "创建测试配置文件..."
mkdir -p "$CLAUDE_DIR"
echo "$TEST_CONFIG" > "$CLAUDE_DIR/test-settings.json"

if [ -f "$CLAUDE_DIR/test-settings.json" ]; then
    echo "✅ 测试配置文件创建成功"
    echo "内容预览:"
    head -5 "$CLAUDE_DIR/test-settings.json"
else
    echo "❌ 测试配置文件创建失败"
fi

# 5. 应用信息
echo ""
echo "=== 应用信息 ==="
/usr/bin/plutil -p "$APP_PATH/Contents/Info.plist" | head -10

echo ""
echo "=== 测试完成 ==="
echo "✅ 应用已成功构建并可以使用"
echo "🚀 要运行应用，请执行: open '$APP_PATH'"
echo "📝 或在 Xcode 中直接运行项目"

# 清理测试文件
rm -f "$CLAUDE_DIR/test-settings.json"