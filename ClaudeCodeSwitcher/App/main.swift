import Cocoa

// MARK: - Application Entry Point 应用程序入口

/// 应用程序启动入口
/// Application entry point with manual NSApplication lifecycle

print("应用启动...")

// 获取共享的 NSApplication 实例
// Get shared NSApplication instance
let app = NSApplication.shared
print("NSApplication 创建成功")

// 创建应用委托
// Create app delegate
let delegate = AppDelegate()
print("AppDelegate 创建成功")

// 设置委托
// Set delegate
app.delegate = delegate
print("设置 delegate 成功")

// 启动应用主循环
// Start application main loop
print("开始运行应用...")
app.run()
