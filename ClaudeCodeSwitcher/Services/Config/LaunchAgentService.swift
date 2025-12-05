import Foundation

/// Launch Agent 管理服务
/// Manages macOS Launch Agent for auto-startup functionality
class LaunchAgentService {

    // MARK: - Singleton

    static let shared = LaunchAgentService()

    private init() {}

    // MARK: - Public Methods

    /// 更新 Launch Agent 状态
    /// Update Launch Agent status
    /// - Parameter shouldAutoStart: 是否应该自动启动 / Whether should auto start
    func updateStatus(_ shouldAutoStart: Bool) {
        if shouldAutoStart {
            install()
        } else {
            remove()
        }
    }

    /// 检查 Launch Agent 是否已安装并加载
    /// Check if Launch Agent is installed and loaded
    /// - Returns: 是否已安装 / Whether is installed
    func checkStatus() -> Bool {
        let plistPath = getPlistPath()

        // 检查 plist 文件是否存在
        // Check if plist file exists
        guard FileManager.default.fileExists(atPath: plistPath.path) else {
            return false
        }

        // 检查 launchctl 是否已加载
        // Check if loaded in launchctl
        let bundleIdentifier = getBundleIdentifier()
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["list", bundleIdentifier]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        task.launch()
        task.waitUntilExit()

        return task.terminationStatus == 0
    }

    // MARK: - Private Methods

    /// 安装 Launch Agent
    /// Install Launch Agent
    private func install() {
        let launchAgentsDir = getLaunchAgentsDirectory()
        let bundleIdentifier = getBundleIdentifier()
        let plistPath = getPlistPath()

        print("正在安装 Launch Agent...")
        print("Bundle Identifier: \(bundleIdentifier)")
        print("Plist 路径: \(plistPath.path)")

        // 确保 LaunchAgents 目录存在
        // Ensure LaunchAgents directory exists
        do {
            try FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
            print("LaunchAgents 目录创建成功")
        } catch {
            print("创建 LaunchAgents 目录失败: \(error)")
            return
        }

        // 获取应用程序路径和可执行文件名称
        // Get application path and executable name
        guard let bundlePath = Bundle.main.bundlePath as String?,
              let executableName = Bundle.main.executablePath?.components(separatedBy: "/").last else {
            print("无法获取应用程序路径或可执行文件名称")
            return
        }

        let executablePath = "\(bundlePath)/Contents/MacOS/\(executableName)"

        print("应用路径: \(bundlePath)")
        print("可执行文件路径: \(executablePath)")
        print("可执行文件名称: \(executableName)")

        // 生成 plist 内容
        // Generate plist content
        let plistContent = generatePlistContent(
            bundleIdentifier: bundleIdentifier,
            executablePath: executablePath,
            bundlePath: bundlePath
        )

        // 写入 plist 文件
        // Write plist file
        do {
            try plistContent.write(to: plistPath, atomically: true, encoding: .utf8)
            print("Launch Agent plist 文件写入成功: \(plistPath.path)")

            // 验证文件是否真的写入了
            // Verify file is written
            if FileManager.default.fileExists(atPath: plistPath.path) {
                print("Plist 文件验证成功")
            } else {
                print("Plist 文件验证失败 - 文件不存在")
                return
            }

            // 先卸载旧的 Launch Agent（如果存在）
            // Unload old Launch Agent if exists
            print("正在卸载旧的 Launch Agent...")
            let unloadTask = Process()
            unloadTask.launchPath = "/bin/launchctl"
            unloadTask.arguments = ["unload", plistPath.path]
            unloadTask.launch()
            unloadTask.waitUntilExit()
            print("卸载操作完成，退出码: \(unloadTask.terminationStatus)")

            // 加载新的 Launch Agent
            // Load new Launch Agent
            print("正在加载新的 Launch Agent...")
            let loadTask = Process()
            loadTask.launchPath = "/bin/launchctl"
            loadTask.arguments = ["load", plistPath.path]
            loadTask.launch()
            loadTask.waitUntilExit()

            if loadTask.terminationStatus == 0 {
                print("Launch Agent 加载成功")

                // 验证是否真的加载了
                // Verify if loaded
                let verifyTask = Process()
                verifyTask.launchPath = "/bin/launchctl"
                verifyTask.arguments = ["list", bundleIdentifier]
                verifyTask.launch()
                verifyTask.waitUntilExit()

                if verifyTask.terminationStatus == 0 {
                    print("Launch Agent 验证成功 - 已在 launchctl 列表中")
                } else {
                    print("Launch Agent 验证失败 - 不在 launchctl 列表中")
                }
            } else {
                print("Launch Agent 加载失败，退出码: \(loadTask.terminationStatus)")

                // 获取错误输出
                // Get error output
                let errorTask = Process()
                errorTask.launchPath = "/bin/launchctl"
                errorTask.arguments = ["load", plistPath.path]
                let errorPipe = Pipe()
                errorTask.standardError = errorPipe
                errorTask.launch()
                errorTask.waitUntilExit()

                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                if let errorMessage = String(data: errorData, encoding: .utf8) {
                    print("Launch Agent 错误信息: \(errorMessage)")
                }
            }
        } catch {
            print("Launch Agent 安装失败: \(error)")
        }
    }

    /// 移除 Launch Agent
    /// Remove Launch Agent
    private func remove() {
        let plistPath = getPlistPath()
        let bundleIdentifier = getBundleIdentifier()

        // 卸载 Launch Agent
        // Unload Launch Agent
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["unload", plistPath.path]
        task.launch()
        task.waitUntilExit()

        // 删除 plist 文件
        // Delete plist file
        do {
            try FileManager.default.removeItem(at: plistPath)
            print("Launch Agent 移除成功")
        } catch {
            print("Launch Agent 移除失败: \(error)")
        }

        // 同时清理旧的 plist 文件（如果存在）
        // Also clean up old plist file if exists
        let launchAgentsDir = getLaunchAgentsDirectory()
        let oldPlistPath = launchAgentsDir.appendingPathComponent("com.example.ClaudeCodeSwitcher.plist")
        if FileManager.default.fileExists(atPath: oldPlistPath.path) {
            do {
                try FileManager.default.removeItem(at: oldPlistPath)
                print("已清理旧的 Launch Agent 文件")
            } catch {
                print("清理旧 Launch Agent 文件失败: \(error)")
            }
        }
    }

    // MARK: - Helper Methods

    /// 获取 LaunchAgents 目录
    /// Get LaunchAgents directory
    private func getLaunchAgentsDirectory() -> URL {
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
    }

    /// 获取 Bundle Identifier
    /// Get Bundle Identifier
    private func getBundleIdentifier() -> String {
        return Bundle.main.bundleIdentifier ?? "com.example.ClaudeCodeSwitcher"
    }

    /// 获取 plist 文件路径
    /// Get plist file path
    private func getPlistPath() -> URL {
        let launchAgentsDir = getLaunchAgentsDirectory()
        let bundleIdentifier = getBundleIdentifier()
        return launchAgentsDir.appendingPathComponent("\(bundleIdentifier).plist")
    }

    /// 生成 plist 文件内容
    /// Generate plist file content
    private func generatePlistContent(bundleIdentifier: String, executablePath: String, bundlePath: String) -> String {
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(bundleIdentifier)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(executablePath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
            <key>LSUIElement</key>
            <true/>
            <key>WorkingDirectory</key>
            <string>\(bundlePath)</string>
        </dict>
        </plist>
        """
    }
}
