import AppKit

/// 剪贴板的唯一读取处：先文本，后图片。
/// 顺序要紧——Word / Excel / Keynote 复制时同时给文本和图片，用户要的是文本；
/// 截图与网页图片则只有图片数据，自然落到 .image。
enum Clipboard {
    case text(String)
    case image(NSImage)
    case empty

    static func read() -> Clipboard {
        let pasteboard = NSPasteboard.general
        let text = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !text.isEmpty { return .text(text) }
        if let image = NSImage(pasteboard: pasteboard) { return .image(image) }
        return .empty
    }
}
