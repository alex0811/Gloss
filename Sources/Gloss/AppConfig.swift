import Foundation

/// 网络层读配置的门面：永远读「当前启用」的服务商档案。
/// Translator / ModelCatalog / OpenAIAPI 只认这三个值，不感知多档案的存在。
enum AppConfig {
    static var baseURL: String {
        ProviderRepo.active()?.baseURL ?? ""
    }

    static var model: String {
        ProviderRepo.active()?.model ?? ""
    }

    static var apiKey: String {
        guard let provider = ProviderRepo.active() else { return "" }
        return KeychainStore.read(account: provider.keychainAccount) ?? ""
    }
}
