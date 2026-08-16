import AppKit
import Combine
import SwiftUI

/// 非激活浮动面板：不抢当前 App 的焦点（气质准则「如行间注」）。
/// 常驻：点击其他地方不收起。关闭方式：再按一次热键 / 浮层右上角 ×。
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
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: PanelLayout.text.size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.contentView = NSHostingView(rootView: TranslationView())
        return panel
    }

    /// 尺寸的唯一事实在 PanelLayout，这里只负责把它落到 NSPanel 上。
    /// 锚住左上角再改尺寸——setContentSize 锚的是左下，高度一变浮层就上蹿下跳；改完整体收回屏幕内。
    private func apply(_ layout: PanelLayout) {
        guard let panel else { return }
        let topLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        panel.setContentSize(layout.size)
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
