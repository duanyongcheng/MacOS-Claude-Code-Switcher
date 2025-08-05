import SwiftUI

struct AddProviderView: View {
    @Binding var isPresented: Bool
    let providerManager: ProviderManager
    @State private var providerName: String = ""
    @State private var providerURL: String = ""
    @State private var apiKey: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("添加新的 API 提供商")
                    .font(.system(size: 16, weight: .semibold))
                
                Spacer()
                
                Button(action: {
                    isPresented = false
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            
            Divider()
            
            // Form
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("提供商名称")
                        .font(.system(size: 13, weight: .medium))
                    
                    TextField("例如：OpenAI", text: $providerName)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("API 基础 URL")
                        .font(.system(size: 13, weight: .medium))
                    
                    TextField("https://api.openai.com/v1", text: $providerURL)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("API 密钥")
                        .font(.system(size: 13, weight: .medium))
                    
                    SecureField("sk-...", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                }
                
                Text("请确保 API 密钥具有适当的权限")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(20)
            
            Divider()
            
            // Buttons
            HStack {
                Button("取消") {
                    isPresented = false
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                
                Spacer()
                
                Button("添加提供商") {
                    providerManager.addProvider(name: providerName, url: providerURL, apiKey: apiKey)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(providerName.isEmpty || providerURL.isEmpty || apiKey.isEmpty)
            }
            .padding(20)
        }
        .frame(width: 400, height: 300)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct AddProviderView_Previews: PreviewProvider {
    static var previews: some View {
        AddProviderView(isPresented: .constant(true), providerManager: ProviderManager())
    }
}