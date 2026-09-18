import Foundation
import NaturalLanguage

/// 一个词写在哪种文字（书写系统）上。切词与判定只有这一份实现，两处读它：
/// 一句话总结拿它数长短（`Summary`），本地预检拿它看「这些词是不是都用目标语言的文字写的」。
enum Script {
    case han, kana, hangul, latin, cyrillic
    /// 数字、以及不归上面任何一种的文字。数字不属于任何语言，预检不拿它算数。
    case other

    /// 把文本切成「词」，每个词记下它写在什么文字上。
    /// 中日韩一字一词——字与字之间不留空格，断不成词；拉丁、西里尔按空白与标点断，
    /// 一个词的文字由它第一个字母定（`abc123` 是一个拉丁词，`1234` 谁的词都不是）。
    static func words(in text: String) -> [Script] {
        var words: [Script] = []
        var insideWord = false
        // 正在攒的这个词是否已经认出文字——认出之前先按 .other 记着，遇到第一个字母再改写
        var identified = false
        for scalar in text.unicodeScalars {
            let script = of(scalar)
            switch script {
            case .han, .kana, .hangul:
                words.append(script)
                insideWord = false
            case .latin, .cyrillic, .other:
                guard CharacterSet.alphanumerics.contains(scalar) else {
                    insideWord = false
                    continue
                }
                if !insideWord {
                    words.append(.other)
                    insideWord = true
                    identified = false
                }
                if !identified, script != .other {
                    words[words.count - 1] = script
                    identified = true
                }
            }
        }
        return words
    }

    private static func of(_ scalar: Unicode.Scalar) -> Script {
        switch scalar.value {
        case 0x3400...0x4DBF,   // 汉字扩展 A
             0x4E00...0x9FFF,   // 汉字基本区
             0xF900...0xFAFF:   // 汉字兼容区
            return .han
        case 0x3040...0x30FF:   // 平假名、片假名
            return .kana
        case 0xAC00...0xD7AF:   // 谚文
            return .hangul
        case 0x0400...0x04FF:   // 西里尔
            return .cyrillic
        case 0x41...0x5A, 0x61...0x7A, 0xC0...0x24F:    // 拉丁，含带变音符号的
            return .latin
        default:
            return .other
        }
    }
}

extension Language {
    /// 这门语言写在什么文字上。简体与繁体在这里是同一套——它俩之间的分辨归识别器管。
    var scripts: Set<Script> {
        switch self {
        case .chinese, .traditionalChinese: [.han]
        case .japanese: [.han, .kana]
        case .korean: [.hangul, .han]
        case .english, .french, .german, .spanish: [.latin]
        case .russian: [.cyrillic]
        }
    }

    /// `Language.rawValue` 与 `NLLanguage.rawValue` 本就是同一套 BCP-47 标签（zh-Hans、ja、ru…），
    /// 直接借过来用，不另立一张映射表——多一张表就多一处要记得同步改的地方。
    var recognized: NLLanguage { NLLanguage(rawValue: rawValue) }
}

/// 本地预检：整段原文本就是目标语言时，一次请求都不必发。
///
/// 两道闸门，各补对方的盲区，都过了才算数：
/// - **文字**：这些词是不是都用目标语言的文字写的。识别器在这里是瞎的——
///   半中半英的一段，它一口咬定 `en:0.999`，只信它就会把该译的当成已经译好的。
/// - **识别器**：同一套文字上的几门语言只能靠它分——简体与繁体、英法德西彼此之间。
///
/// 判错的两个方向轻重不同：漏判（该省的没省）只是照旧发一次请求，误判（不该省的省了）
/// 是用户按了快捷键却什么也没等到。所以两道闸门都从严，宁可漏判。
enum Precheck {
    /// 太短就别猜：「你好」两个字，识别器会以 0.804 一口咬定是繁体。
    /// 数据落在这条线两边——2 个词判错，6 个词以上各语种都稳。算的是目标语言那些词，不是全部。
    private static let minimumWords = 6
    /// 夹几个外文专名、术语不算数（「这个功能依赖 Vision 框架」仍是中文），但半中半英的必须拦下。
    private static let purity = 0.9
    private static let confidence = 0.9

    /// 整段原文是不是已经是目标语言了。
    static func isAlreadyTarget(_ text: String) -> Bool {
        let target = TranslationPref.target
        let words = Script.words(in: text)
        let own = words.filter { target.scripts.contains($0) }.count
        guard own >= minimumWords else { return false }
        // 数字、符号不属于任何语言，不进分母：一串价格、编号不该把纯度稀释掉
        let spelled = words.filter { $0 != .other }.count
        guard Double(own) / Double(spelled) >= purity else { return false }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        // 只取最像的那一门：概率过得了 0.9，它必然就是第一名
        guard let top = recognizer.languageHypotheses(withMaximum: 1).first else { return false }
        return top.key == target.recognized && top.value >= confidence
    }
}
