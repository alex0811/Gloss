// 本地预检（Sources/Gloss/Precheck.swift）的对账表：三个常数——最少词数 6、纯度 0.9、置信 0.9——
// 靠这张表定，不靠手感。改动其中任何一个之前先跑这里，看它翻掉哪几例。
// 两半：一是切词与旧 Summary.wordCount 等价（切词收敛成一份时不许悄悄改了总结的长短判据），
// 二是预检的期望表。期望里「该跳过」和「该翻译」轻重不同：漏判只是照旧发一次请求，
// 误判是用户按了快捷键却什么也没等到——所以两道闸门都从严，表里宁可多几条 false。
// 用法：swiftc -O -parse-as-library Sources/Gloss/Language.swift Sources/Gloss/Precheck.swift Scripts/precheck-check.swift -o /tmp/precheck-check && /tmp/precheck-check
import Foundation
import NaturalLanguage

/// 收敛之前 Summary 里的那份 wordCount，原样抄来比对——等价与否由它说了算。
func oldWordCount(_ text: String) -> Int {
    func isIdeographic(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF: return true
        default: return false
        }
    }
    var count = 0
    var insideWord = false
    for s in text.unicodeScalars {
        if isIdeographic(s) {
            count += 1
            insideWord = false
        } else if CharacterSet.alphanumerics.contains(s) {
            if !insideWord { count += 1 }
            insideWord = true
        } else {
            insideWord = false
        }
    }
    return count
}

@main
struct PrecheckCheck {
  static func main() {
    var failed = 0

    let countCases = ["", "1234", "abc123", "123abc", "你好世界", "café au lait", "汉abc汉",
      "The build failed again last night", "这个 API 的 callback 在主线程执行，记得先 merge 一下 branch。",
      "오늘 회의", "На сегодняшней встрече", "こんにちは世界", "¥99.00 和 1,234 件", "a-b-c", "emoji 🎉 test"]
    for t in countCases where oldWordCount(t) != Script.words(in: t).count {
        failed += 1
        print("✗ 切词不等价：旧 \(oldWordCount(t)) / 新 \(Script.words(in: t).count) :: \(t)")
    }
    print("切词与旧 wordCount 等价：\(countCases.count) 例")
    print("---")

    // expect = 预检该不该放行（true＝就地交回原文，不发请求）
    let cases: [(Language, String, Bool, String)] = [
      (.chinese, "今天的会议主要讨论了下一个季度的产品规划，我们需要在月底之前完成所有的设计稿并提交评审。", true, "纯简体长"),
      (.chinese, "这个功能依赖 Vision 框架，识别结果会按行返回。", true, "简体夹一个术语"),
      (.chinese, "今天的会议主要讨论了下一个季度的产品规划，我们需要在月底之前完成设计稿。相关文档在 Notion 上。", true, "简体长夹术语"),
      (.chinese, "明天下午三点开会，别迟到了", true, "简体12字"),
      (.chinese, "你好", false, "简体2字-太短"),
      (.chinese, "确定", false, "简体2字-太短"),
      (.chinese, "这个 API 的 callback 在主线程执行，记得先 merge 一下 branch。", false, "简体半数术语"),
      (.chinese, "今天的会议 discussed the roadmap for next quarter, 我们需要在月底之前完成设计稿。", false, "中英混杂一半"),
      (.chinese, "这段代码有问题。The callback is never invoked when the socket closes early. 需要修一下。", false, "中文夹一句英文"),
      (.chinese, "明天下午三點開會，別遲到了，記得帶上文件", false, "繁体-目标简体"),
      (.chinese, "今日の会議では来四半期の製品計画について話し合いました。", false, "日文-目标简体"),
      (.chinese, "The meeting today covered the product roadmap for next quarter.", false, "英文-目标简体"),
      (.traditionalChinese, "今天的會議主要討論了下一個季度的產品規劃，我們需要在月底之前完成所有的設計稿。", true, "纯繁体-目标繁体"),
      (.traditionalChinese, "今天的会议主要讨论了下一个季度的产品规划，我们需要在月底之前完成所有的设计稿。", false, "简体-目标繁体"),
      (.english, "The meeting today covered the product roadmap for next quarter and what we owe the board.", true, "纯英文"),
      (.english, "The build failed again last night", true, "英文6词"),
      (.english, "See you tomorrow", false, "英文3词-太短"),
      (.english, "OK", false, "英文-太短"),
      (.english, "La réunion d'aujourd'hui portait sur la feuille de route du produit pour le trimestre.", false, "法文-目标英文"),
      (.english, "Das heutige Meeting drehte sich um die Produkt-Roadmap für das nächste Quartal.", false, "德文-目标英文"),
      (.english, "今天的会议 discussed the roadmap for next quarter, 我们需要在月底之前完成设计稿。", false, "中英混杂-目标英文"),
      (.english, "这段代码有问题。The callback is never invoked when the socket closes early. 需要修一下。", false, "中文夹英文-目标英文"),
      (.english, "https://github.com/anthropics/claude-code/issues/123", true, "URL-目标英文本就无需译"),
      (.english, "1234 5678 ¥99.00", false, "纯数字"),
      (.english, "let x = foo.bar(baz: 1)\nprint(x)", false, "纯代码-太短"),
      (.japanese, "今日の会議では来四半期の製品計画について話し合いました。", true, "日文-目标日文"),
      (.japanese, "今天的会议主要讨论了下一个季度的产品规划。", false, "中文-目标日文"),
      (.korean, "오늘 회의에서는 다음 분기 제품 계획에 대해 논의했습니다.", true, "韩文-目标韩文"),
      (.russian, "На сегодняшней встрече мы обсудили планы по продукту на следующий квартал.", true, "俄文-目标俄文"),
      (.french, "La réunion d'aujourd'hui portait sur la feuille de route du produit pour le trimestre.", true, "法文-目标法文"),
      (.german, "Das heutige Meeting drehte sich um die Produkt-Roadmap für das nächste Quartal.", true, "德文-目标德文"),
      (.spanish, "La reunión de hoy trató sobre la hoja de ruta del producto para el próximo trimestre.", true, "西语-目标西语"),
      (.english, "", false, "空串"),
    ]

    for (language, text, expect, name) in cases {
        TranslationPref.target = language
        let got = Precheck.isAlreadyTarget(text)
        guard got != expect else { continue }
        failed += 1
        // 误判（不该放行却放行了）是危险的那一头，漏判只是白发一次请求
        print("✗ \(got ? "误判" : "漏判")：[\(language.rawValue)] \(name)")
    }
    print("预检对账：\(cases.count) 例")
    print(failed == 0 ? "\n全对 ✓" : "\n\(failed) 例不符 ✗")
    exit(failed == 0 ? 0 : 1)
  }
}
