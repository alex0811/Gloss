import AppKit
import Combine
import SwiftUI

/// 非激活浮动面板：不抢当前 App 的焦点（气质准则「如行间注」）。
/// 关闭方式：点浮层外任意处 / 再按一次热键 / 浮层右上角 ×。
@MainActor
final class PanelController {
    private var panel: NSPanel?
    private var clickMonitor: Any?
    private var sizeCancellable: AnyCancellable?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        observeSizeChanges()
        syncContentSize()
        position(panel)
        panel.orderFrontRegardless()
        installClickMonitor()
    }

    func hide() {
        panel?.orderOut(nil)
        removeClickMonitor()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 320),
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

    /// 视图高度是唯一事实：图片模式 400，其余 320。
    private func syncContentSize() {
        let height: CGFloat = AppState.shared.displaysSourceImage ? 400 : 320
        panel?.setContentSize(NSSize(width: 440, height: height))
    }

    /// 设置页切换「显示原图」时，正显示的浮层跟着变高矮。
    /// 订阅只能放在 show() 里——init 期间 AppState.shared 还在构造，反向访问会重入。
    private func observeSizeChanges() {
        guard sizeCancellable == nil else { return }
        sizeCancellable = AppState.shared.$showsSourceImage
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in self?.syncContentSize() }
            }
    }

    /// 出现在鼠标附近，并整体收进当前屏幕的可见区域。
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        var origin = NSPoint(x: mouse.x + 12, y: mouse.y - panel.frame.height - 12)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - panel.frame.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - panel.frame.height - 8)
        panel.setFrameOrigin(origin)
    }

    /// 全局鼠标监听只收到其他 App 的点击（点浮层自身不会触发），天然实现「点外面即关」。
    private func installClickMonitor() {
        removeClickMonitor()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            Task { @MainActor in AppState.shared.dismiss() }
        }
    }

    private func removeClickMonitor() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }
}
