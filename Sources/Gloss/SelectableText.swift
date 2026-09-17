import AppKit
import SwiftUI

/// 可框选的译文区。
/// SwiftUI 的 .textSelection 背后是个文本框，得窗成为 key、拿到编辑焦点才吃得到拖拽——
/// 无边框浮层当不了 key 窗（见 TranslationPanel），于是怎么拖都选不动。
/// 换成 NSTextView：不等窗成为 key 就能拖选，key 只是为了 ⌘C；
/// 双击选词、三击选段、右键复制都是它自带的本事，流式追加也不冲掉已经选好的一段。
struct SelectableText: NSViewRepresentable {
    let text: String
    let font: NSFont
    let color: NSColor

    func makeNSView(context: Context) -> NSScrollView {
        SelectableTextView.scrollable()
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        (scrollView.documentView as? SelectableTextView)?.show(text, font: font, color: color)
    }
}

/// 译文这块地方：拖拽归选字不归挪窗，也是浮层里唯一开口要键盘焦点的视图（为了 ⌘C）。
/// 前两条本就是 NSTextView 的默认，这里钉死——它们悄悄变了，框选和 ⌘C 会不声不响地失灵。
final class SelectableTextView: NSTextView {
    override var mouseDownCanMoveWindow: Bool { false }
    override var needsPanelToBecomeKey: Bool { true }
    /// 浮层不抢前台 App 的焦点，所以第一下点击就得直接开始选字，不能只用来「点亮窗口」
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// I 形光标：NSTextView 自带的走光标矩形，只在 key 窗里生效，浮层平时不是 key 窗，
    /// 于是和缩放区一样靠常驻的鼠标跟踪自己设（后台设光标能生效的前提见 BackgroundCursor）。
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let own = iBeamTracking { removeTrackingArea(own) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        iBeamTracking = area
    }

    private var iBeamTracking: NSTrackingArea?

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        NSCursor.iBeam.set()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        NSCursor.arrow.set()
    }

    /// 装进滚动视图：宽度跟着浮层走、只在纵向长个儿，译文只换行不会横向溢出成一条长龙。
    static func scrollable() -> NSScrollView {
        let textView = SelectableTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        // 文字位置与原来的 SwiftUI Text 严丝合缝：不留内边距，也不留行片段默认的 5 点留白
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        return scrollView
    }

    /// 换内容。样式的事实就在文本自己身上，不另存一份：样式没变，才谈得上「只是又长了一截」。
    func show(_ text: String, font: NSFont, color: NSColor) {
        guard let storage = textStorage else { return }
        let sameStyle = storage.length == 0 || (
            storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont == font
                && storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == color
        )
        let current = string
        guard !(sameStyle && current == text) else { return }
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if sameStyle, text.hasPrefix(current) {
            // 流式只补新长出来的那一截：全文不重排，用户已经框选的一段也不会被抹掉
            storage.append(NSAttributedString(string: String(text.dropFirst(current.count)), attributes: attributes))
        } else {
            storage.setAttributedString(NSAttributedString(string: text, attributes: attributes))
        }
    }
}
