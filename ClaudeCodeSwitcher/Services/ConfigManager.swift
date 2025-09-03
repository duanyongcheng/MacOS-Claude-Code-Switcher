import Foundation
import Combine
import AppKit

class ConfigManager: ObservableObject {
    static let shared = ConfigManager()
    
    @Published var providers: [APIProvider] = []
    @Published var currentProvider: APIProvider?
    @Published var autoUpdate: Bool = true
    @Published var proxyHost: String = ""
    @Published var proxyPort: String = ""
    @Published var autoStartup: Bool = false
    
    private let userDefaults = UserDefaults.standard
    private let claudeConfigPath: URL
    
    private init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        claudeConfigPath = homeDir.appendingPathComponent(".claude/settings.json")
        loadConfiguration()
    }
    
    // MARK: - Public Methods
    
    func getProviders() -> [APIProvider] {
        return providers
    }
    
    func addProvider(_ provider: APIProvider) {
        providers.append(provider)
        saveConfiguration()
        syncToClaudeConfig()
        postConfigChangeNotification()
    }
    
    func updateProvider(_ provider: APIProvider) {
        if let index = providers.firstIndex(where: { $0.id == provider.id }) {
            providers[index] = provider
            
            // 如果更新的是当前提供商，也要更新当前提供商
            if currentProvider?.id == provider.id {
                currentProvider = provider
            }
            
            saveConfiguration()
            syncToClaudeConfig()
            postConfigChangeNotification()
        }
    }
    
    func removeProvider(_ provider: APIProvider) {
        providers.removeAll { $0.id == provider.id }
        
        // 如果删除的是当前提供商，清空当前提供商
        if currentProvider?.id == provider.id {
            currentProvider = nil
        }
        
        saveConfiguration()
        syncToClaudeConfig()
        postConfigChangeNotification()
    }
    
    func setCurrentProvider(_ provider: APIProvider) {
        currentProvider = provider
        saveConfiguration()
        syncToClaudeConfig()
        postConfigChangeNotification()
    }
    
    func copyProvider(_ provider: APIProvider) {
        let copiedProvider = APIProvider(
            name: provider.name + "-复制",
            url: provider.url,
            key: provider.key,
            largeModel: provider.largeModel,
            smallModel: provider.smallModel
        )
        providers.append(copiedProvider)
        saveConfiguration()
        syncToClaudeConfig()
        postConfigChangeNotification()
    }
    
    func updateGlobalSettings(autoUpdate: Bool, proxyHost: String, proxyPort: String, autoStartup: Bool) {
        self.autoUpdate = autoUpdate
        self.proxyHost = proxyHost
        self.proxyPort = proxyPort
        
        // 更新开机自启动设置
        let wasAutoStartup = self.autoStartup
        self.autoStartup = autoStartup
        
        if wasAutoStartup != autoStartup {
            updateLaunchAgentStatus(autoStartup)
        } else if autoStartup {
            // 如果开机自启已启用但状态不正确，重新安装
            if !checkLaunchAgentStatus() {
                print("检测到 Launch Agent 状态不正确，重新安装...")
                updateLaunchAgentStatus(true)
            }
        }
        
        saveConfiguration()
        syncToClaudeConfig()
        postConfigChangeNotification()
    }
    
    // MARK: - Private Methods
    
    private func loadConfiguration() {
        // 从 UserDefaults 加载配置
        if let data = userDefaults.data(forKey: "providers"),
           let decodedProviders = try? JSONDecoder().decode([APIProvider].self, from: data) {
            providers = decodedProviders
        }
        
        if let data = userDefaults.data(forKey: "currentProvider"),
           let decodedProvider = try? JSONDecoder().decode(APIProvider.self, from: data) {
            currentProvider = decodedProvider
        }
        
        autoUpdate = userDefaults.bool(forKey: "autoUpdate")
        proxyHost = userDefaults.string(forKey: "proxyHost") ?? ""
        proxyPort = userDefaults.string(forKey: "proxyPort") ?? ""
        autoStartup = userDefaults.bool(forKey: "autoStartup")
    }
    
    private func saveConfiguration() {
        // 保存到 UserDefaults
        if let data = try? JSONEncoder().encode(providers) {
            userDefaults.set(data, forKey: "providers")
        }
        
        if let currentProvider = currentProvider,
           let data = try? JSONEncoder().encode(currentProvider) {
            userDefaults.set(data, forKey: "currentProvider")
        } else {
            userDefaults.removeObject(forKey: "currentProvider")
        }
        
        userDefaults.set(autoUpdate, forKey: "autoUpdate")
        userDefaults.set(proxyHost, forKey: "proxyHost")
        userDefaults.set(proxyPort, forKey: "proxyPort")
        userDefaults.set(autoStartup, forKey: "autoStartup")
    }
    
    private func syncToClaudeConfig() {
        do {
            // 确保 .claude 目录存在
            let claudeDir = claudeConfigPath.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: claudeDir.path) {
                try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
            }
            
            // 读取现有配置作为原始 JSON（保留所有字段）
            var existingJson: [String: Any] = [:]
            if FileManager.default.fileExists(atPath: claudeConfigPath.path) {
                let data = try Data(contentsOf: claudeConfigPath)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    existingJson = json
                }
            }
            
            // 更新仅由 Switcher 管理的字段
            updateSwitcherManagedFields(&existingJson)
            
            // 写入配置文件
            let data = try JSONSerialization.data(withJSONObject: existingJson, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: claudeConfigPath)
            
            print("已同步配置到 Claude 配置文件: \(claudeConfigPath.path)")
            
        } catch {
            print("同步 Claude 配置失败: \(error)")
        }
    }
    
    private func updateSwitcherManagedFields(_ json: inout [String: Any]) {
        // 确保 env 对象存在
        var env = (json["env"] as? [String: Any]) ?? [:]
        
        // 只更新 Switcher 管理的字段
        if let provider = currentProvider {
            env["ANTHROPIC_API_KEY"] = provider.key
            env["ANTHROPIC_BASE_URL"] = provider.url
            
            // 可选字段：只在有值时设置，否则移除
            if let largeModel = provider.largeModel, !largeModel.isEmpty {
                env["ANTHROPIC_MODEL"] = largeModel
            } else {
                env.removeValue(forKey: "ANTHROPIC_MODEL")
            }
            
            if let smallModel = provider.smallModel, !smallModel.isEmpty {
                env["ANTHROPIC_SMALL_FAST_MODEL"] = smallModel
            } else {
                env.removeValue(forKey: "ANTHROPIC_SMALL_FAST_MODEL")
            }
        } else {
            // 没有当前提供商时，清空这些字段
            env["ANTHROPIC_API_KEY"] = ""
            env["ANTHROPIC_BASE_URL"] = ""
            env.removeValue(forKey: "ANTHROPIC_MODEL")
            env.removeValue(forKey: "ANTHROPIC_SMALL_FAST_MODEL")
        }
        
        // 处理代理设置
        let proxyUrl = buildProxyUrl()
        if !proxyUrl.isEmpty {
            env["HTTPS_PROXY"] = proxyUrl
            env["HTTP_PROXY"] = proxyUrl
        } else {
            env.removeValue(forKey: "HTTPS_PROXY")
            env.removeValue(forKey: "HTTP_PROXY")
        }
        
        // 更新 env 对象
        json["env"] = env
    }
    
    private func buildProxyUrl() -> String {
        guard !proxyHost.isEmpty else { return "" }
        
        let host = proxyHost
        let port = proxyPort.isEmpty ? "" : ":\(proxyPort)"
        let url = "\(host)\(port)"
        
        if url.hasPrefix("http://") || url.hasPrefix("https://") {
            return url
        } else {
            return "http://\(url)"
        }
    }
    
    private func postConfigChangeNotification() {
        NotificationCenter.default.post(name: .configDidChange, object: nil)
    }
    
    // MARK: - Launch Agent Management
    
    private func updateLaunchAgentStatus(_ shouldAutoStart: Bool) {
        if shouldAutoStart {
            installLaunchAgent()
        } else {
            removeLaunchAgent()
        }
    }
    
    // 检查开机自启状态
    func checkLaunchAgentStatus() -> Bool {
        let launchAgentsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.example.ClaudeCodeSwitcher"
        let plistPath = launchAgentsDir.appendingPathComponent("\(bundleIdentifier).plist")
        
        // 检查 plist 文件是否存在
        guard FileManager.default.fileExists(atPath: plistPath.path) else {
            return false
        }
        
        // 检查 launchctl 是否已加载
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
    
    private func installLaunchAgent() {
        let launchAgentsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
        
        // 使用正确的 bundle identifier，避免硬编码
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.example.ClaudeCodeSwitcher"
        let plistPath = launchAgentsDir.appendingPathComponent("\(bundleIdentifier).plist")
        
        print("正在安装 Launch Agent...")
        print("Bundle Identifier: \(bundleIdentifier)")
        print("Plist 路径: \(plistPath.path)")
        
        // 确保 LaunchAgents 目录存在
        do {
            try FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
            print("LaunchAgents 目录创建成功")
        } catch {
            print("创建 LaunchAgents 目录失败: \(error)")
            return
        }
        
        // 获取应用程序路径和可执行文件名称
        guard let bundlePath = Bundle.main.bundlePath as String? else {
            print("无法获取应用程序路径")
            return
        }
        
        guard let executableName = Bundle.main.executablePath?.components(separatedBy: "/").last else {
            print("无法获取可执行文件名称")
            return
        }
        
        let executablePath = "\(bundlePath)/Contents/MacOS/\(executableName)"
        
        print("应用路径: \(bundlePath)")
        print("可执行文件路径: \(executablePath)")
        print("可执行文件名称: \(executableName)")
        
        let plistContent = """
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
        
        do {
            try plistContent.write(to: plistPath, atomically: true, encoding: .utf8)
            print("Launch Agent plist 文件写入成功: \(plistPath.path)")
            
            // 验证文件是否真的写入了
            if FileManager.default.fileExists(atPath: plistPath.path) {
                print("Plist 文件验证成功")
            } else {
                print("Plist 文件验证失败 - 文件不存在")
                return
            }
            
            // 先卸载旧的 Launch Agent（如果存在）
            print("正在卸载旧的 Launch Agent...")
            let unloadTask = Process()
            unloadTask.launchPath = "/bin/launchctl"
            unloadTask.arguments = ["unload", plistPath.path]
            unloadTask.launch()
            unloadTask.waitUntilExit()
            print("卸载操作完成，退出码: \(unloadTask.terminationStatus)")
            
            // 加载新的 Launch Agent
            print("正在加载新的 Launch Agent...")
            let loadTask = Process()
            loadTask.launchPath = "/bin/launchctl"
            loadTask.arguments = ["load", plistPath.path]
            loadTask.launch()
            loadTask.waitUntilExit()
            
            if loadTask.terminationStatus == 0 {
                print("Launch Agent 加载成功")
                
                // 验证是否真的加载了
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
    
    private func removeLaunchAgent() {
        let launchAgentsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
        
        // 使用与安装时相同的 bundle identifier
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.example.ClaudeCodeSwitcher"
        let plistPath = launchAgentsDir.appendingPathComponent("\(bundleIdentifier).plist")
        
        // 卸载 Launch Agent
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["unload", plistPath.path]
        task.launch()
        task.waitUntilExit()
        
        // 删除 plist 文件
        do {
            try FileManager.default.removeItem(at: plistPath)
            print("Launch Agent 移除成功")
        } catch {
            print("Launch Agent 移除失败: \(error)")
        }
        
        // 同时清理旧的 plist 文件（如果存在）
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
}

// MARK: - Notification Names
extension Notification.Name {
    static let configDidChange = Notification.Name("configDidChange")
}
