import Foundation

/// 一门可以译成的语言。原文语种不在这里——那是模型的事，Gloss 只说「译成什么」。
/// rawValue 会落进 UserDefaults，是存档的钥匙，别改。
enum Language: String, CaseIterable, Identifiable {
    case chinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case spanish = "es"
    case russian = "ru"

    var id: String { rawValue }

    /// 设置页显示它，prompt 里也用它称呼这门语言——只有一个名字，说给谁听都一样。
    var name: String {
        switch self {
        case .chinese: "简体中文"
        case .traditionalChinese: "繁体中文"
        case .english: "英语"
        case .japanese: "日语"
        case .korean: "韩语"
        case .french: "法语"
        case .german: "德语"
        case .spanish: "西班牙语"
        case .russian: "俄语"
        }
    }
}

/// 目标语言的唯一出入口（nonisolated：翻译请求在后台读）。写只经 `AppState`。
enum LanguagePref {
    private static let targetKey = "targetLanguage"
    private static var defaults: UserDefaults { .standard }

    static var target: Language {
        get { defaults.string(forKey: targetKey).flatMap(Language.init(rawValue:)) ?? .chinese }
        set { defaults.set(newValue.rawValue, forKey: targetKey) }
    }

    /// 「译成什么」全项目只说这一次：文本与图片逐行两份 prompt 都取它。
    /// 原文是什么语种不必交代——模型自己认得，多说一句反而会限制它。
    static var directive: String {
        "不论原文是什么语种，一律译成\(target.name)"
    }
}
