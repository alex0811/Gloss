import AppKit
import Combine
import SwiftUI

/// 非激活浮动面板：不抢当前 App 的焦点（气质准则「如行间注」）。
/// 默认是普通层级的窗：切到别的 App 会被盖住，但不收起；右上角图钉置顶后浮在所有窗之上。
/// 关法只有两种：浮层露在外面时再按一次热键 / 浮层右上角 ×。
/// 拖边缘调大小；文本模式调好的大小记下来，下次照此弹出。
@MainActor
final class PanelController {
    private var panel: NSPanel?
    private var sizeCancellable: AnyCancellable?
    private var notificationTokens: [NSObjectProtocol] = []

    var isVisible: Bool { panel?.isVisible ?? false }

    /// 浮层归宿的屏幕：正显示就是它所在的屏，还没弹出就是即将弹出的（鼠标所在）屏。
    /// 图片模式算布局要按这块屏的大小和缩放来。
    var targetScreen: NSScreen? {
        if let panel, panel.isVisible { return panel.screen ?? PanelScreen.current }
        return PanelScreen.current
    }

    /// 浮层露没露出来：没显示、或被别的窗整个盖住都算没露。热键据此决定是收起还是先亮出来。
    var isExposed: Bool {
        guard let panel, panel.isVisible else { return false }
        return panel.occlusionState.contains(.visible)
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

    /// 置顶浮在所有窗之上；不置顶就是普通窗，切到别的 App，它的窗照常盖过来。
    func setPinned(_ pinned: Bool) {
        panel?.level = pinned ? .floating : .normal
    }

    private func makePanel() -> NSPanel {
        let panel = TranslationPanel(
            contentRect: NSRect(origin: .zero, size: PanelLayout.text.size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = AppState.shared.isPinned ? .floating : .normal
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
        keepFrontAfterMissionControl()
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

    /// 在调度中心（Mission Control）里选中浮层，系统会激活 Gloss、把浮层提到最前，
    /// 可约 0.25 秒后（实测 0.22–0.27 秒，退场动画收尾时）又把前台还给先前的 App，那边的窗随之盖回来。
    /// 探针里单纯激活一个只有 nonactivatingPanel 的 accessory App，前台并不会被还回去，
    /// 所以还前台的是调度中心那一侧，拦不住，只能跟着再提一次。
    /// 判据：Gloss 刚被激活后不久，别的 App 在没有按着鼠标的情况下被激活——这不是用户点过去的。
    /// 用户自己点别的 App 时鼠标正按着，浮层照常被盖住。
    private func keepFrontAfterMissionControl() {
        let window: TimeInterval = 0.6
        var activatedAt: Date?
        notificationTokens.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            activatedAt = Date()
        })
        notificationTokens.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app != .current,
                  let since = activatedAt, Date().timeIntervalSince(since) < window,
                  NSEvent.pressedMouseButtons == 0
            else { return }
            activatedAt = nil
            // 那边的窗在激活通知之后才提上来，排到下一拍再提浮层
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let panel = self?.panel, panel.isVisible else { return }
                    panel.orderFrontRegardless()
                }
            }
        })
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

    /// 被别的窗盖住一半时点它，要能把它提上来。Gloss 从不激活，系统不会替一个后台 App 的窗调整前后，自己提。
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            orderFrontRegardless()
        }
        super.sendEvent(event)
    }

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
