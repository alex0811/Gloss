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

/// 翻译偏好的唯一出入口（nonisolated：翻译请求在后台读）。写只经 `AppState`。
/// 「译成什么」和「用户写给译者的话」都从这里进 prompt：文本、图片逐行两份翻译 prompt 共用开头，
/// 再加上一句话总结（`Summary.prompt`），三份共用结尾那段用户偏好。
enum TranslationPref {
    private static let targetKey = "targetLanguage"
    private static let notesKey = "translationNotes"
    private static var defaults: UserDefaults { .standard }

    static var target: Language {
        get { defaults.string(forKey: targetKey).flatMap(Language.init(rawValue:)) ?? .chinese }
        set { defaults.set(newValue.rawValue, forKey: targetKey) }
    }

    /// 用户自己写的翻译偏好：常读什么领域、哪些词保留原文。
    /// 这是模型从一段原文里看不出来的事——「commit」「PR」单拎出来，它不知道你天天读代码。
    static var notes: String {
        get { defaults.string(forKey: notesKey) ?? "" }
        set { defaults.set(newValue, forKey: notesKey) }
    }

    /// 两份翻译 prompt 只各写自己的规矩（`rules`），角色、目标语言在这里拼一次。
    /// 原文是什么语种不必交代——模型自己认得，多说一句反而会限制它。
    static func systemPrompt(rules: String) -> String {
        withNotes("你是一名专业译者，不论原文是什么语种，一律译成\(target.name)。\(rules)")
    }

    /// 用户偏好统一缀在最后，并声明从属于上文的规矩：用户写「多解释几句」，
    /// 既不该让图片逐行的行号格式散掉，也不该让一句话总结长成三句。
    /// 翻译与总结（见 `Summary.prompt`）共用这条尾巴——偏好只有一份，说给谁听都一样。
    static func withNotes(_ prompt: String) -> String {
        let notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !notes.isEmpty else { return prompt }
        return prompt + "\n\n以下是用户写给译者的翻译偏好，在不违背上述要求的前提下遵循：\n\(notes)"
    }
}

/// 翻译偏好的起手稿，不是另一种模式：选中只是把这段话填进输入框，prompt 永远只认输入框里的字。
/// 于是「选了哪个预设」和「框里写了什么」不会是两份状态，填进去之后照样随手改。
/// 措辞不写死「中文」：译成什么由 `TranslationPref.target` 说，预设只说领域的规矩。
enum NotesPreset: String, CaseIterable, Identifiable {
    case programming
    case academic
    case business
    case casual

    var id: String { rawValue }

    var name: String {
        switch self {
        case .programming: "编程 / 技术"
        case .academic: "学术论文"
        case .business: "商务沟通"
        case .casual: "日常口语"
        }
    }

    var text: String {
        switch self {
        case .programming:
            "我读的多是编程和软件开发相关的英文。API、SDK、commit、PR、issue、merge、branch、callback 等业界通用术语保留英文原文，不硬译；"
                + "函数名、变量名、命令、报错信息原样保留。其余按技术文档的习惯译，简洁直白，不要翻译腔。"
        case .academic:
            "我读的多是学术论文。术语译法前后一致，专业术语首次出现时在译文后用括号附上原文；"
                + "公式、引用标注、缩写原样保留；语气严谨客观，不增删论证。"
        case .business:
            "我读的多是工作邮件和商务沟通。保持原文的礼貌程度和语气；人名、公司名、日期、金额准确保留；"
                + "译文自然得体，像母语者写的。"
        case .casual:
            "我读的多是社交媒体、聊天记录和日常对话。译得口语化、自然；俚语和网络用语按意思译，不逐字直译。"
        }
    }
}
