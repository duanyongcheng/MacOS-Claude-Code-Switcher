import SwiftUI
import Foundation

class ProviderManager: ObservableObject {
    @Published var providers: [APIProvider] = []
    
    private let userDefaults = UserDefaults.standard
    private let providersKey = "api_providers"
    
    init() {
        loadProviders()
    }
    
    func loadProviders() {
        if let data = userDefaults.data(forKey: providersKey),
           let decodedProviders = try? JSONDecoder().decode([APIProvider].self, from: data) {
            providers = decodedProviders
        } else {
            // Load default providers
            providers = [
                APIProvider(name: "鸭子-新加坡", url: "https://sg.instcopilot-api.com", apiKey: ""),
                APIProvider(name: "鸭子-日本", url: "https://jp.instcopilot-api.com", apiKey: ""),
                APIProvider(name: "鸭子-香港", url: "https://hk.instcopilot-api.com", apiKey: "")
            ]
        }
    }
    
    func saveProviders() {
        if let encoded = try? JSONEncoder().encode(providers) {
            userDefaults.set(encoded, forKey: providersKey)
        }
    }
    
    func addProvider(name: String, url: String, apiKey: String) {
        let newProvider = APIProvider(name: name, url: url, apiKey: apiKey)
        providers.append(newProvider)
        saveProviders()
    }
    
    func deleteProvider(at index: Int) {
        guard index < providers.count else { return }
        providers.remove(at: index)
        saveProviders()
    }
    
    func deleteProvider(with id: UUID) {
        providers.removeAll { $0.id == id }
        saveProviders()
    }
    
    func updateProvider(_ provider: APIProvider) {
        if let index = providers.firstIndex(where: { $0.id == provider.id }) {
            providers[index] = provider
            saveProviders()
        }
    }
}

struct APIProvider: Identifiable, Codable {
    let id = UUID()
    var name: String
    var url: String
    var apiKey: String
    var isActive: Bool = true
    
    enum CodingKeys: String, CodingKey {
        case name, url, apiKey, isActive
    }
    
    init(name: String, url: String, apiKey: String, isActive: Bool = true) {
        self.name = name
        self.url = url
        self.apiKey = apiKey
        self.isActive = isActive
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        url = try container.decode(String.self, forKey: .url)
        apiKey = try container.decode(String.self, forKey: .apiKey)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(url, forKey: .url)
        try container.encode(apiKey, forKey: .apiKey)
        try container.encode(isActive, forKey: .isActive)
    }
}