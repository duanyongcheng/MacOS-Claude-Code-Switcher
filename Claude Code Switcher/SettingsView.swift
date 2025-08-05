import SwiftUI

struct SettingsView: View {
    @StateObject private var providerManager = ProviderManager()
    @State private var totalCost: Double = 897.3592
    @State private var totalConversations: Int = 99
    @State private var totalTokens: String = "417.06M"
    @State private var lastUpdate: String = "11:48"
    @State private var showingAddProvider = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            // Info Card
            infoCardView
            
            // API Providers Section
            apiProvidersView
            
            Spacer()
        }
        .frame(width: 520, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showingAddProvider) {
            AddProviderView(isPresented: $showingAddProvider, providerManager: providerManager)
        }
    }
    
    private var headerView: some View {
        HStack {
            Text("Claude Code Switcher")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.primary)
            
            Spacer()
            
            Button(action: {
                NSApplication.shared.keyWindow?.close()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }
    
    private var infoCardView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("INFO")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    
                    Text("查看您的 Claude Code API 使用情况和成本")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    // Refresh action
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            // Stats Grid - More compact layout
            HStack(spacing: 24) {
                // Total Cost
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("总成本")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    Text("$\(String(format: "%.4f", totalCost))")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                }
                
                // Total Conversations
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                        Text("总会话")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    Text("\(totalConversations)")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                }
                
                // Total Tokens
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 8, height: 8)
                        Text("总令牌")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    Text(totalTokens)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                }
            }
            
            HStack {
                Spacer()
                Text("最后更新: \(lastUpdate)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
    
    private var apiProvidersView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("API 提供商")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 20)
                
                Text("添加和管理自定义 API 提供商")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 20)
            }
            
            // Add Provider Button
            Button(action: {
                showingAddProvider = true
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.blue)
                    
                    Text("添加新提供商")
                        .font(.system(size: 13, weight: .medium))
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .padding(.horizontal, 20)
            
            // Provider List
            if !providerManager.providers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("已添加的提供商")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 20)
                    
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(providerManager.providers) { provider in
                                ProviderRow(provider: provider, providerManager: providerManager)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "cloud.slash")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Text("暂无 API 提供商")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    
                    Text("点击上方按钮添加您的第一个提供商")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .padding(.vertical, 32)
            }
        }
        .padding(.top, 8)
    }
}

struct ProviderRow: View {
    let provider: APIProvider
    let providerManager: ProviderManager
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Circle()
                        .fill(provider.isActive ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                        
                        if !isExpanded {
                            Text(provider.url)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        Button(action: {
                            providerManager.deleteProvider(with: provider.id)
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundColor(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                        .padding(.horizontal, 12)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Base URL")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        
                        Text(provider.url)
                            .font(.system(size: 12))
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, 12)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("API Key")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        
                        Text(provider.apiKey.isEmpty ? "未设置" : String(repeating: "•", count: min(provider.apiKey.count, 32)))
                            .font(.system(size: 12))
                            .foregroundColor(provider.apiKey.isEmpty ? .secondary : .primary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}