import Foundation

/// UserDefaults key 的单一来源（设置界面 @AppStorage 与读取方共用）。
enum ConfigKey {
    static let baseURL = "baseURL"
    static let model = "model"
}

enum AppConfig {
    private static var defaults: UserDefaults { .standard }

    static var baseURL: String {
        defaults.string(forKey: ConfigKey.baseURL) ?? ""
    }

    static var model: String {
        defaults.string(forKey: ConfigKey.model) ?? ""
    }

    static var apiKey: String {
        KeychainStore.read() ?? ""
    }
}
