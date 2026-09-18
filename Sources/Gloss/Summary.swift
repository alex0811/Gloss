import Foundation

/// 一句话总结的规矩：「怎么跟模型说」和「什么时候值得说」是同一个事实，只写在这一处。
/// 总结是注的注——译文仍是主，它只在译文长到一眼看不完时才出现。
enum Summary {
    /// 总结的对象是译完的全文，不是半截：压一段还在流的译文，压出来的话不作数（气质准则「忠实」）。
    static var prompt: String {
        TranslationPref.withNotes("""
        你是一名严谨的编辑。下面是一段译文，用\(TranslationPref.target.name)把它压成一句话，\
        交代它整体在说什么。只输出这一句：不写「总结」之类的开头，不分行、不列点，不超过 60 字。\
        只压缩已有的内容，不添加原文没有的信息，不作评价。
        """)
    }

    /// 一眼看得完的译文不必再压一句——短文上的总结只是噪音（气质准则「简短」）。
    /// 这条线画在「一屏读不完」处：浮层出厂大小的译文区约莫装得下 130 个汉字，
    /// 到 100 词就该有一句话先领着，不必等到要滚动才给。
    /// 中日韩一字算一词、拉丁语系按词断，折算到同一把尺上再比：两边读起来都是二十秒上下的量。
    static func deserves(_ text: String) -> Bool { wordCount(text) >= 100 }

    /// 长短按词数量：切词与「中日韩一字一词」的规矩不写在这里，与本地预检共用一份（见 `Script`）。
    private static func wordCount(_ text: String) -> Int { Script.words(in: text).count }
}
