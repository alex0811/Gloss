import AppKit

/// 菜单栏模板图标，几何与 Design/MenuBarIcon.svg 一致：
/// 一条细文本线 + 一条粗短注线（两元素，避免 ☰ 误读），纯黑由系统着色。
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setFill()
            NSBezierPath(
                roundedRect: NSRect(x: 2, y: 5.2, width: 14, height: 1.8),
                xRadius: 0.9, yRadius: 0.9
            ).fill()
            NSBezierPath(
                roundedRect: NSRect(x: 2, y: 9.4, width: 9, height: 3.6),
                xRadius: 1.8, yRadius: 1.8
            ).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
