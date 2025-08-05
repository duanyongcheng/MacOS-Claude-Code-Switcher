# Claude Code Switcher for macOS

一个用于快速切换 Claude Code API 提供商配置的 macOS 状态栏应用。

## 功能特性

- 🔄 **快速切换** - 在状态栏点击即可切换不同的 API 提供商
- ⚙️ **配置管理** - 添加、编辑、删除自定义 API 提供商
- 🔄 **自动同步** - 实时同步配置到 `~/.claude/settings.json`
- 🌐 **代理支持** - 支持 HTTP/HTTPS 代理设置
- 🔔 **通知反馈** - 切换时显示系统通知
- 💾 **数据持久化** - 配置保存在本地，重启后仍然有效

## 系统要求

- macOS 13.0 或更高版本
- Xcode 15.0 或更高版本（仅用于编译）

## 构建说明

1. **克隆项目**
   ```bash
   git clone <repository-url>
   cd MacOS-Claude-Code-Switcher
   ```

2. **使用 Xcode 打开项目**
   ```bash
   open ClaudeCodeSwitcher.xcodeproj
   ```

3. **编译运行**
   - 在 Xcode 中选择目标设备为 "My Mac"
   - 按 `Cmd + R` 运行项目
   - 或者按 `Cmd + B` 仅构建项目

4. **发布构建**
   ```bash
   # 在项目根目录执行
   xcodebuild -project ClaudeCodeSwitcher.xcodeproj -scheme ClaudeCodeSwitcher -configuration Release clean build
   ```

## 使用方法

### 初次设置

1. 启动应用后，在状态栏会出现一个大脑图标
2. 点击图标，选择"设置..."打开配置窗口
3. 在"API 提供商"标签页中点击"添加提供商"
4. 填写提供商信息：
   - **名称**: 自定义名称（如 "OpenAI", "Claude Official" 等）
   - **API URL**: API 端点地址
   - **API 密钥**: 对应的 API 密钥
   - **大模型**: （可选）指定大模型名称
   - **小模型**: （可选）指定小模型名称

### 切换提供商

1. 点击状态栏图标
2. 从下拉菜单中选择要使用的 API 提供商
3. 系统会显示切换成功的通知
4. Claude Code 将自动使用新的配置

### 全局设置

在设置窗口的"全局设置"标签页中可以配置：
- **自动更新**: 是否启用自动更新
- **代理设置**: HTTP/HTTPS 代理服务器和端口

## 配置文件

应用会将配置同步到 `~/.claude/settings.json`，Claude Code 会自动读取这个文件中的配置。

配置文件结构：
```json
{
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "your-api-key",
    "ANTHROPIC_BASE_URL": "your-api-url",
    "ANTHROPIC_MODEL": "large-model-name",
    "ANTHROPIC_SMALL_FAST_MODEL": "small-model-name",
    "DISABLE_AUTOUPDATER": "0",
    "HTTPS_PROXY": "proxy-url",
    "HTTP_PROXY": "proxy-url"
  }
}
```

## 故障排除

### 应用无法启动
- 检查 macOS 版本是否符合要求
- 确保已授予必要的权限（文件访问、通知）

### 配置同步失败
- 检查 `~/.claude` 目录是否存在且可写
- 确保没有其他进程正在使用 settings.json 文件

### 通知不显示
- 在系统偏好设置 > 通知中启用应用的通知权限

## 开发说明

项目结构：
```
ClaudeCodeSwitcher/
├── App/                    # 应用主体
│   ├── main.swift         # 应用入口
│   ├── AppDelegate.swift  # 应用委托
│   ├── StatusBarController.swift  # 状态栏控制
│   └── SettingsWindowController.swift  # 设置窗口
├── Models/                # 数据模型
│   ├── APIProvider.swift  # API 提供商模型
│   └── ClaudeConfig.swift # Claude 配置模型
├── Services/              # 业务服务
│   └── ConfigManager.swift  # 配置管理
├── Views/                 # 用户界面
│   └── SettingsView.swift   # SwiftUI 设置界面
└── Resources/             # 资源文件
    ├── Info.plist
    ├── Assets.xcassets
    └── ClaudeCodeSwitcher.entitlements
```

## 许可证

[请添加适当的许可证信息]

## 贡献

欢迎提交 Issue 和 Pull Request！

## 支持

如有问题请创建 Issue 或联系开发者。