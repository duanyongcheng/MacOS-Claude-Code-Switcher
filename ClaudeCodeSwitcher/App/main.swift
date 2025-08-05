import Cocoa

print("应用启动...")

let app = NSApplication.shared
print("NSApplication 创建成功")

let delegate = AppDelegate()
print("AppDelegate 创建成功")

app.delegate = delegate
print("设置 delegate 成功")

print("开始运行应用...")
app.run()