import Foundation

/// 图片逐行翻译的行规：行号是译文对回原图位置的唯一钥匙。
/// 「怎么跟模型说」「怎么发出去」「怎么收回来」是同一个事实，三面都只写在这一处——
/// 换个标记法只改这一个文件，格式对不上在结构上就不会发生。
enum LineFormat {
    static let prompt = """
    你是一名专业译者，在中文与英文之间互译：原文以英文为主译成简体中文，以中文为主译成英文。\
    输入是图片里逐行识别出的文字，每行以「[行号] 」开头。译文也逐行输出：每行以相同的行号开头，\
    行号一一对应，不合并、不拆分、不省略、不改行号，一行译文写成一行不折行。\
    每行译文独立成句、简洁通顺，脱离上下文也能读懂；专有名词与技术术语保持一致。只输出译文行，不解释。
    """

    static func encode(_ lines: [RecognizedLine]) -> String {
        lines.map { "[\($0.id)] \($0.text)" }.joined(separator: "\n")
    }

    /// 行号只在行首算数：正文里的「[1]」（维基百科那种引用标注）不会被误当成行号，把后面的字抢走。
    /// 行号之后一律收到行尾，所以译文里带方括号也不会被截断。
    private static let marker = try! NSRegularExpression(
        pattern: #"^[ \t]*[\[【](\d{1,3})[\]】][ \t:：]*(.*)$"#,
        options: .anchorsMatchLines
    )

    /// 从流式缓冲里抠出「行号 → 译文」：每来一块就全量重扫，末行的残句随流长全。
    /// 收尾时若模型彻底无视行号，退回按顺序对位；行数对不上宁可不对位，也不张冠李戴。
    static func decode(_ buffer: String, count: Int, final: Bool) -> [Int: String] {
        let text = buffer as NSString
        var found: [Int: String] = [:]
        marker.enumerateMatches(
            in: buffer, range: NSRange(location: 0, length: text.length)
        ) { match, _, _ in
            guard let match,
                  let number = Int(text.substring(with: match.range(at: 1))),
                  number >= 1, number <= count
            else { return }
            found[number] = text.substring(with: match.range(at: 2))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if !found.isEmpty || !final { return found }

        let plain = buffer.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard count > 0, plain.count == count else { return [:] }
        return Dictionary(uniqueKeysWithValues: (1...count).map { ($0, plain[$0 - 1]) })
    }

    /// 剥掉行号，其余原样交出——模型多说的、没按行号说的，一个字不吞。
    /// 图上只叠对得上号的行，下方内容区照单全收，两边各司其职。
    static func strip(_ buffer: String) -> String {
        marker.stringByReplacingMatches(
            in: buffer,
            range: NSRange(location: 0, length: (buffer as NSString).length),
            withTemplate: "$2"
        )
    }
}
