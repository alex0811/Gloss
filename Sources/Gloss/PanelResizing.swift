import AppKit
import Darwin

/// 浮层的拖边缩放，自己做而不交给系统：无边框窗即便带 .resizable，边上不给缩放光标，
/// 拖起来也不经 setFrame、不认 contentMinSize，能一路拖到连按钮都看不见。
/// 窗口四周一圈铺八块把手（四边四角），光标、拖拽都在把手上，下限只读 PanelLayout.minSize。
///
/// 为什么是一块块把手而不是容器自己判断落点：拖背景挪窗是窗口服务器按「哪些视图 mouseDownCanMoveWindow 为假」
/// 算出的挡板区域来做的，按视图矩形算，不问 hitTest。容器整块说「不能挪」，整扇窗就都拖不动了；
/// 只有把手自己说「不能挪」，挡板才恰好是边上那一圈，其余照旧拖背景挪窗。
final class ResizableContainerView: NSView {
    /// 拖到哪几条边。
    struct Edges: OptionSet, Hashable {
        let rawValue: Int
        static let left = Edges(rawValue: 1 << 0)
        static let right = Edges(rawValue: 1 << 1)
        static let top = Edges(rawValue: 1 << 2)
        static let bottom = Edges(rawValue: 1 << 3)
    }

    /// 边上可拖的宽度，全在窗内：浮层内容有 16 点内边距，这一圈压不到按钮和译文。
    static let edgeWidth: CGFloat = 5
    /// 角上的把手是这么大的方块，比边宽，斜拖更好对准。
    static let cornerLength: CGFloat = 14

    /// 一次拖拽结束（松手）时调用。
    var onResizeEnd: (() -> Void)?

    private let handles: [ResizeHandle]

    init(content: NSView) {
        let all: [Edges] = [.left, .right, .top, .bottom,
                            [.top, .left], [.top, .right], [.bottom, .left], [.bottom, .right]]
        handles = all.map(ResizeHandle.init)
        super.init(frame: content.frame)
        content.frame = bounds
        content.autoresizingMask = [.width, .height]
        addSubview(content)
        // 加在内容之后，叠在最上层：落在边上的点击先到把手
        for handle in handles {
            handle.onResizeEnd = { [weak self] in self?.onResizeEnd?() }
            addSubview(handle)
        }
        placeHandles()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// 容器本身不挡挪窗，挡板只来自把手。
    override var mouseDownCanMoveWindow: Bool { true }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        placeHandles()
    }

    /// 把手位置由当下 bounds 现算，不靠 autoresizing 从初始尺寸（可能是零）推。
    private func placeHandles() {
        for handle in handles {
            handle.frame = Self.handleFrame(for: handle.edges, in: bounds)
        }
    }

    /// 视图坐标（y 向上）里某块把手占的矩形。角是方块；边是两角之间的细条。纯函数，好验证。
    static func handleFrame(for edges: Edges, in bounds: NSRect) -> NSRect {
        let corner = cornerLength, edge = edgeWidth
        let horizontal = edges.isDisjoint(with: [.left, .right]) ? nil : edges.contains(.left)
        let vertical = edges.isDisjoint(with: [.top, .bottom]) ? nil : edges.contains(.bottom)
        switch (horizontal, vertical) {
        case let (isLeft?, isBottom?):
            return NSRect(x: isLeft ? bounds.minX : bounds.maxX - corner,
                          y: isBottom ? bounds.minY : bounds.maxY - corner,
                          width: corner, height: corner)
        case let (isLeft?, nil):
            return NSRect(x: isLeft ? bounds.minX : bounds.maxX - edge, y: bounds.minY + corner,
                          width: edge, height: max(bounds.height - corner * 2, 0))
        case let (nil, isBottom?):
            return NSRect(x: bounds.minX + corner, y: isBottom ? bounds.minY : bounds.maxY - edge,
                          width: max(bounds.width - corner * 2, 0), height: edge)
        case (nil, nil):
            return .zero
        }
    }

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

    static func cursor(for edges: Edges) -> NSCursor {
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
}

/// 一块缩放把手：挡住挪窗、给缩放光标、按住拖就改窗框。
private final class ResizeHandle: NSView {
    let edges: ResizableContainerView.Edges
    var onResizeEnd: (() -> Void)?

    init(edges: ResizableContainerView.Edges) {
        self.edges = edges
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

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

    override func mouseEntered(with event: NSEvent) {
        ResizableContainerView.cursor(for: edges).set()
    }

    override func mouseMoved(with event: NSEvent) {
        ResizableContainerView.cursor(for: edges).set()
    }

    /// 把手都在内容的 16 点内边距里，离开把手落到的只会是背景，还原成箭头即可。
    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let startFrame = window.frame
        let startMouse = NSEvent.mouseLocation
        let minFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: PanelLayout.minSize)).size
        let edges = edges
        window.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: .infinity, mode: .eventTracking) { next, stop in
            guard let next else { return }
            if next.type == .leftMouseUp {
                stop.pointee = true
                return
            }
            let mouse = NSEvent.mouseLocation
            let delta = CGVector(dx: mouse.x - startMouse.x, dy: mouse.y - startMouse.y)
            window.setFrame(ResizableContainerView.frame(from: startFrame, dragging: edges, by: delta, minSize: minFrame),
                            display: true)
            ResizableContainerView.cursor(for: edges).set()
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
