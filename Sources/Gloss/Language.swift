import Foundation

/// 一门语言的全部事实：UI 怎么写、跟模型怎么称呼、Vision 用哪个识别标签。
/// rawValue 会落进 UserDefaults，是存档的钥匙，别改。
enum Language: String, CaseIterable, Identifiable {
    case auto
    case english = "en"
    case chinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case spanish = "es"
    case russian = "ru"

    var id: String { rawValue }

    /// 加一门语言就加这一行：名字与识别标签在同一处定，两边不会各说各话。
    /// 识别标签取 Vision 认得的写法（macOS 13+ 均支持）；「自动」不对应任何单一语种。
    private var facts: (name: String, vision: String?) {
        switch self {
        case .auto: ("自动检测", nil)
        case .english: ("英语", "en-US")
        case .chinese: ("简体中文", "zh-Hans")
        case .traditionalChinese: ("繁体中文", "zh-Hant")
        case .japanese: ("日语", "ja-JP")
        case .korean: ("韩语", "ko-KR")
        case .french: ("法语", "fr-FR")
        case .german: ("德语", "de-DE")
        case .spanish: ("西班牙语", "es-ES")
        case .russian: ("俄语", "ru-RU")
        }
    }

    /// 设置页显示它，prompt 里也用它称呼这门语言——只有一个名字，说给谁听都一样。
    var name: String { facts.name }

    /// Vision 的识别语种标签；「自动」没有，由调用方决定摆哪些。
    var visionCode: String? { facts.vision }

    /// 译文语言不能是「自动」：候选里就没有它，而不是选完再校验。
    static let targets = allCases.filter { $0 != .auto }
}

/// 语言偏好的唯一出入口（nonisolated：翻译请求与图片识别都在后台读）。
/// 写只经 `AppState`，读遍布 Translator / LineFormat / OCR。
enum LanguagePref {
    private static let sourceKey = "sourceLanguage"
    private static let targetKey = "targetLanguage"
    private static var defaults: UserDefaults { .standard }

    static var source: Language {
        get { read(sourceKey) ?? .english }
        set { defaults.set(newValue.rawValue, forKey: sourceKey) }
    }

    static var target: Language {
        get { read(targetKey) ?? .chinese }
        set { defaults.set(newValue.rawValue, forKey: targetKey) }
    }

    /// 「译成什么」这句话全项目只说一次：文本 prompt 与图片逐行 prompt 都取它，
    /// 换语言、改措辞都只动这一处，两份 prompt 说的不可能不一致。
    static var directive: String {
        let source = source
        guard source != .auto else {
            return "自动判断原文语种，一律译成\(target.name)"
        }
        return "把\(source.name)原文译成\(target.name)"
    }

    private static func read(_ key: String) -> Language? {
        defaults.string(forKey: key).flatMap(Language.init(rawValue:))
    }
}
