import AppKit
import Darwin

/// 浮层的拖边缩放，自己做而不交给系统：无边框窗即便带 .resizable，边上不给缩放光标，
/// 拖起来也不经 setFrame、不认 contentMinSize，能一路拖到连按钮都看不见。
/// 这里接管窗口四周一圈：光标、拖拽、下限都在这一处，下限只读 PanelLayout.minSize。
final class ResizableContainerView: NSView {
    /// 拖到哪几条边。
    struct Edges: OptionSet, Equatable {
        let rawValue: Int
        static let left = Edges(rawValue: 1 << 0)
        static let right = Edges(rawValue: 1 << 1)
        static let top = Edges(rawValue: 1 << 2)
        static let bottom = Edges(rawValue: 1 << 3)
    }

    /// 边上可拖的宽度，全在窗内：浮层内容有 16 点内边距，这一圈压不到按钮和译文。
    static let edgeWidth: CGFloat = 5
    /// 角上放宽一些，斜拖更好对准。
    static let cornerLength: CGFloat = 14

    /// 一次拖拽结束（松手）时调用。
    var onResizeEnd: (() -> Void)?

    private var showsResizeCursor = false

    init(content: NSView) {
        super.init(frame: content.frame)
        content.frame = bounds
        content.autoresizingMask = [.width, .height]
        addSubview(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// 由起始窗框、拖动的边和鼠标位移算新窗框：拖动的边跟着鼠标，对边钉在原地，到下限就停。
    /// 坐标是屏幕坐标（y 向上）。纯函数，好验证。
    static func frame(from start: NSRect, dragging edges: Edges, by delta: CGVector, minSize: CGSize) -> NSRect {
        var rect = start
        if edges.contains(.right) {
            rect.size.width = max(minSize.width, start.width + delta.dx)
        } else if edges.contains(.left) {
            rect.size.width = max(minSize.width, start.width - delta.dx)
            rect.origin.x = start.maxX - rect.width
        }
        if edges.contains(.top) {
            rect.size.height = max(minSize.height, start.height + delta.dy)
        } else if edges.contains(.bottom) {
            rect.size.height = max(minSize.height, start.height - delta.dy)
            rect.origin.y = start.maxY - rect.height
        }
        return rect
    }

    /// 视图坐标（y 向上）里这一点落在哪几条边上；空集即不在缩放区。
    func edges(at point: NSPoint) -> Edges {
        guard bounds.contains(point) else { return [] }
        let near = { (distance: CGFloat, along: CGFloat) -> Bool in
            distance < Self.edgeWidth || (distance < Self.cornerLength && along < Self.cornerLength)
        }
        var edges: Edges = []
        let fromLeft = point.x, fromRight = bounds.maxX - point.x
        let fromBottom = point.y, fromTop = bounds.maxY - point.y
        let alongX = min(fromLeft, fromRight), alongY = min(fromBottom, fromTop)
        if near(fromLeft, alongY) { edges.insert(.left) } else if near(fromRight, alongY) { edges.insert(.right) }
        if near(fromBottom, alongX) { edges.insert(.bottom) } else if near(fromTop, alongX) { edges.insert(.top) }
        return edges
    }

    // MARK: 命中：边上归缩放，其余照旧交给内容

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return super.hitTest(point) }
        return edges(at: convert(point, from: superview)).isEmpty ? super.hitTest(point) : self
    }

    override var mouseDownCanMoveWindow: Bool { false }
    /// 浮层不抢前台焦点，第一下按住就得开始拖，不能只用来点亮窗口
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: 光标：浮层很少是 key 窗，光标矩形不生效，靠常驻的鼠标跟踪自己设
    // 光是设还不够：Gloss 从不成为前台 App，窗口服务器默认不认后台 App 设的光标，见 BackgroundCursor

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursor(for: edges(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        updateCursor(for: [])
    }

    /// 只收拾自己设过的光标：离开缩放区时不去覆盖译文区的 I 形光标。
    private func updateCursor(for edges: Edges) {
        if let cursor = Self.cursor(for: edges) {
            cursor.set()
            showsResizeCursor = true
        } else if showsResizeCursor {
            NSCursor.arrow.set()
            showsResizeCursor = false
        }
    }

    private static func cursor(for edges: Edges) -> NSCursor? {
        guard !edges.isEmpty else { return nil }
        if #available(macOS 15.0, *) {
            let position: NSCursor.FrameResizePosition
            switch edges {
            case [.top, .left]: position = .topLeft
            case [.top, .right]: position = .topRight
            case [.bottom, .left]: position = .bottomLeft
            case [.bottom, .right]: position = .bottomRight
            case .top: position = .top
            case .bottom: position = .bottom
            case .left: position = .left
            default: position = .right
            }
            return .frameResize(position: position, directions: .all)
        }
        // macOS 14 没有公开的斜向缩放光标，角上退回横向的
        return edges.isDisjoint(with: [.left, .right]) ? .resizeUpDown : .resizeLeftRight
    }

    // MARK: 拖拽

    override func mouseDown(with event: NSEvent) {
        let edges = edges(at: convert(event.locationInWindow, from: nil))
        guard let window, !edges.isEmpty else { return super.mouseDown(with: event) }
        let startFrame = window.frame
        let startMouse = NSEvent.mouseLocation
        let minFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: PanelLayout.minSize)).size
        window.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: .infinity, mode: .eventTracking) { next, stop in
            guard let next else { return }
            if next.type == .leftMouseUp {
                stop.pointee = true
                return
            }
            let mouse = NSEvent.mouseLocation
            let delta = CGVector(dx: mouse.x - startMouse.x, dy: mouse.y - startMouse.y)
            window.setFrame(Self.frame(from: startFrame, dragging: edges, by: delta, minSize: minFrame), display: true)
            Self.cursor(for: edges)?.set()
        }
        onResizeEnd?()
    }
}

/// 让后台 App 设的光标生效。Gloss 从不激活（气质准则「如行间注」），不开这个，
/// 缩放区的箭头、译文上的 I 形光标一个都出不来——实测 mouseMoved 照常收到、set() 照常调用，屏幕上就是不变。
/// 公开 API 里没有对应的开关，用的是窗口服务器的连接属性 SetsCursorInBackground（私有）。
/// 运行时按名字找函数：哪天系统拿掉了，退化成没有光标，不会因为链接不到符号启动即崩。
enum BackgroundCursor {
    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SetConnectionProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32

    static func enable() {
        guard
            let handle = dlopen(nil, RTLD_NOW),
            let mainSymbol = dlsym(handle, "CGSMainConnectionID"),
            let setSymbol = dlsym(handle, "CGSSetConnectionProperty")
        else { return }
        let connection = unsafeBitCast(mainSymbol, to: MainConnectionID.self)()
        let set = unsafeBitCast(setSymbol, to: SetConnectionProperty.self)
        _ = set(connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
    }
}
