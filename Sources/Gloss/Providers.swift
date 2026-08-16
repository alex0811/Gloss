import Foundation
import Combine

/// 一份服务商档案：名称 / Base URL / 模型整体切换。
/// API Key 不在这里——按档案 id 存 Keychain，见 `keychainAccount`。
struct Provider: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = ""
    var baseURL = ""
    var model = ""

    var keychainAccount: String { "apiKey.\(id.uuidString)" }

    /// 没起名就用 host 顶着，都没有才叫「未命名」。
    var displayName: String {
        if !name.isEmpty { return name }
        if let host = URL(string: baseURL)?.host { return host }
        return "未命名"
    }
}

/// 档案在 UserDefaults 的唯一出入口（nonisolated：翻译请求在后台读）。
/// 不变式：列表永不为空、activeID 永远指向现存档案——由 `bootstrap()` 一处保证。
enum ProviderRepo {
    private static let providersKey = "providers"
    private static let activeIDKey = "activeProviderID"
    private static var defaults: UserDefaults { .standard }

    static func load() -> [Provider] {
        guard let data = defaults.data(forKey: providersKey),
              let list = try? JSONDecoder().decode([Provider].self, from: data),
              !list.isEmpty
        else { return [] }
        return list
    }

    static func store(_ providers: [Provider]) {
        guard let data = try? JSONEncoder().encode(providers) else { return }
        defaults.set(data, forKey: providersKey)
    }

    static var activeID: UUID? {
        get { defaults.string(forKey: activeIDKey).flatMap(UUID.init) }
        set { defaults.set(newValue?.uuidString, forKey: activeIDKey) }
    }

    static func active() -> Provider? {
        let providers = load()
        guard let id = activeID else { return providers.first }
        return providers.first { $0.id == id } ?? providers.first
    }

    /// 幂等，启动时调用：多档案之前的单份配置（UserDefaults 的 baseURL/model +
    /// Keychain 的 "apiKey"）迁成第一个档案；全新安装则建一个空档案。
    static func bootstrap() {
        var providers = load()
        if providers.isEmpty {
            let first = Provider(
                baseURL: defaults.string(forKey: "baseURL") ?? "",  // 多档案之前的旧 key
                model: defaults.string(forKey: "model") ?? ""
            )
            // 旧 Keychain 账户搬到按档案命名的账户下。读不到（如重签名后被系统拒绝）
            // 或写入失败时，旧条目原地保留——宁可让用户重填一次，不能悄悄丢 key。
            if let legacyKey = KeychainStore.read(account: KeychainStore.legacyAccount),
               !legacyKey.isEmpty,
               KeychainStore.save(legacyKey, account: first.keychainAccount) {
                KeychainStore.delete(account: KeychainStore.legacyAccount)
            }
            providers = [first]
            store(providers)
            defaults.removeObject(forKey: "baseURL")
            defaults.removeObject(forKey: "model")
        }
        if activeID == nil || !providers.contains(where: { $0.id == activeID }) {
            activeID = providers[0].id
        }
    }
}

/// UI 侧的可观察镜像：设置页与菜单栏共同观察，写操作即时落盘。
@MainActor
final class ProviderStore: ObservableObject {
    static let shared = ProviderStore()

    @Published var providers: [Provider] {
        didSet { ProviderRepo.store(providers) }
    }

    @Published var activeID: UUID? {
        didSet { ProviderRepo.activeID = activeID }
    }

    private init() {
        ProviderRepo.bootstrap()
        providers = ProviderRepo.load()
        activeID = ProviderRepo.activeID
    }

    var active: Provider? {
        providers.first { $0.id == activeID }
    }

    var activeIndex: Int? {
        providers.firstIndex { $0.id == activeID }
    }

    func addProvider() {
        let provider = Provider()
        providers.append(provider)
        activeID = provider.id
    }

    /// 删除当前档案并连带清掉它的 Keychain key。
    /// 始终保留至少一个档案：按钮侧已禁用，这里再兜底。
    func removeActive() {
        guard providers.count > 1, let index = activeIndex else { return }
        let removed = providers.remove(at: index)
        KeychainStore.delete(account: removed.keychainAccount)
        activeID = providers[min(index, providers.count - 1)].id
    }
}
