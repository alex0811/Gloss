import AppKit
import Combine
import SwiftUI

/// 非激活浮动面板：不抢当前 App 的焦点（气质准则「如行间注」）。
/// 常驻：点击其他地方不收起。关闭方式：再按一次热键 / 浮层右上角 ×。
/// 拖边缘调大小；文本模式调好的大小记下来，下次照此弹出。
@MainActor
final class PanelController {
    private var panel: NSPanel?
    private var sizeCancellable: AnyCancellable?

    var isVisible: Bool { panel?.isVisible ?? false }

    /// 浮层归宿的屏幕：正显示就是它所在的屏，还没弹出就是即将弹出的（鼠标所在）屏。
    /// 图片模式算布局要按这块屏的大小和缩放来。
    var targetScreen: NSScreen? {
        if let panel, panel.isVisible { return panel.screen ?? PanelScreen.current }
        return PanelScreen.current
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        observeSizeChanges()
        apply(AppState.shared.layout)
        // 常驻中的浮层可能已被拖走，刷新内容时不挪窝；只有新弹出才贴鼠标。
        if !panel.isVisible {
            position(panel)
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = TranslationPanel(
            contentRect: NSRect(origin: .zero, size: PanelLayout.text.size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        // 只有点进译文才借键盘焦点（译文区是唯一说自己需要键盘的视图）：
        // 点关闭、点重新翻译、拖着挪窝都不惊动前台 App。
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        let hostingView = NSHostingView(rootView: TranslationView())
        // 窗口大小归窗口管：不让 SwiftUI 内容的理想尺寸反过来钉住窗口，拖边缘才拖得动
        hostingView.sizingOptions = []
        // 不用 .resizable：系统给无边框窗的缩放没有光标、不认下限，见 ResizableContainerView
        BackgroundCursor.enable()
        let container = ResizableContainerView(content: hostingView)
        container.onResizeEnd = { [weak self] in self?.rememberTextSize() }
        panel.contentView = container
        return panel
    }

    /// 开场尺寸的唯一事实在 PanelLayout，这里只负责把它落到 NSPanel 上；之后用户怎么拖由窗口自己记着。
    /// 锚住左上角再改尺寸——setContentSize 锚的是左下，高度一变浮层就上蹿下跳；改完整体收回屏幕内。
    /// 记下的尺寸可能来自一块更大的屏，放不下就先收到屏幕里。
    private func apply(_ layout: PanelLayout) {
        guard let panel else { return }
        let topLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        var size = layout.size
        if let visible = (panel.screen ?? PanelScreen.current)?.visibleFrame {
            size.width = max(min(size.width, visible.width - 16), PanelLayout.minSize.width)
            size.height = max(min(size.height, visible.height - 16), PanelLayout.minSize.height)
        }
        panel.setContentSize(size)
        panel.setFrameTopLeftPoint(topLeft)
        keepOnScreen(panel)
    }

    /// 布局变了（换图、设置页切开关），正显示的浮层跟着变大小。
    /// 订阅只能放在 show() 里——init 期间 AppState.shared 还在构造，反向访问会重入。
    private func observeSizeChanges() {
        guard sizeCancellable == nil else { return }
        sizeCancellable = AppState.shared.$layout
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] layout in
                Task { @MainActor in self?.apply(layout) }
            }
    }

    /// 文本模式拖完才记；图片模式的大小跟着那张图走，不算用户的偏好。
    private func rememberTextSize() {
        guard let panel, AppState.shared.layout.image == nil else { return }
        PanelLayout.textSize = panel.contentLayoutRect.size
    }

    /// 新弹出时出现在鼠标附近。
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        panel.setFrameTopLeftPoint(NSPoint(x: mouse.x + 12, y: mouse.y - 12))
        keepOnScreen(panel)
    }

    /// 整体收进所在屏幕的可见区域。
    private func keepOnScreen(_ panel: NSPanel) {
        guard let visible = (panel.screen ?? PanelScreen.current)?.visibleFrame else { return }
        var origin = panel.frame.origin
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - panel.frame.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - panel.frame.height - 8)
        panel.setFrameOrigin(origin)
    }
}

/// 浮层这扇窗：无边框窗默认当不了 key 窗，当不了就没有键盘焦点——译文选中了也按不动 ⌘C。
/// 允许成为 key，但配上 nonactivatingPanel + becomesKeyOnlyIfNeeded：借键盘不激活 App，
/// 且只在用户点进译文时才借（气质准则「如行间注」——工具是配角，不打断手头的事）。
private final class TranslationPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// 菜单栏 App 没有编辑菜单可挂 ⌘C / ⌘A 的键盘等价物，自己送进响应链交给译文区。
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else { return false }
        switch event.charactersIgnoringModifiers {
        case "c": return NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self)
        case "a": return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self)
        default: return false
        }
    }
}
