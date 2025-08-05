# Claude Code Switcher for macOS - 实现计划

## 项目概述
基于文档需求，实现一个 macOS 状态栏应用，用于快速切换 Claude Code 的 API 提供商配置。

## 核心功能
1. **状态栏集成** - 显示切换图标，提供下拉菜单
2. **API 提供商管理** - 添加、编辑、删除、切换提供商
3. **配置同步** - 实时同步到 `~/.claude/settings.json`
4. **设置界面** - SwiftUI 实现的详细配置窗口
5. **代理支持** - HTTP/HTTPS 代理配置
6. **通知反馈** - 切换状态的用户反馈

## 技术架构
- **Swift + AppKit** - 状态栏和窗口管理
- **SwiftUI** - 现代化设置界面
- **UserDefaults** - 本地配置存储
- **FileManager** - Claude 配置文件操作
- **Codable** - JSON 序列化处理

## 实现分解

### 1. 项目设置阶段
- 创建 macOS App 项目 (SwiftUI + Swift)
- 配置 Info.plist (LSUIElement, 通知权限)
- 设置项目结构和文件组织

### 2. 数据层实现
- **APIProvider 模型** - 提供商信息封装
- **ClaudeConfig 模型** - Claude 配置文件结构
- **数据验证逻辑** - API 密钥和 URL 验证

### 3. 业务逻辑层
- **ConfigManager** - 核心配置管理服务
- **文件操作** - Claude 配置读写同步
- **通知机制** - 配置变更通知

### 4. 用户界面层
- **AppDelegate** - 应用生命周期管理
- **StatusBarController** - 状态栏菜单控制
- **SettingsWindowController** - 设置窗口管理
- **SwiftUI 视图** - 现代化设置界面

### 5. 测试和优化
- 功能测试 - 所有核心功能验证
- 配置同步测试 - Claude Code 集成验证
- 性能优化 - 内存和响应优化

## 开发优先级
1. **高优先级** - 数据模型、配置管理、状态栏控制
2. **中优先级** - 设置界面、窗口管理、权限配置
3. **低优先级** - 图标资源、代码优化、扩展功能

## 实施步骤
1. 分析项目需求和技术架构 ✅
2. 创建 Xcode 项目基础结构
3. 实现数据模型 (APIProvider, ClaudeConfig)
4. 实现配置管理服务 (ConfigManager)
5. 实现应用主入口 (AppDelegate)
6. 实现状态栏控制器 (StatusBarController)
7. 实现设置窗口控制器 (SettingsWindowController)
8. 实现 SwiftUI 设置界面 (SettingsView 及相关视图)
9. 配置项目权限和 Info.plist
10. 添加应用图标和资源文件
11. 测试应用功能和配置同步
12. 优化和代码重构