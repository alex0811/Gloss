import AppKit

/// 浮层「弹出时该多大」的唯一事实：面板按它开场，视图从它读原图尺寸。
/// 开场之后窗口本身就是尺寸的事实——用户拖边缘调大小，视图铺满窗口，不再回头对这份数。
/// 文本模式按用户上次调好的大小开场；图片模式跟着原图长、到屏幕可见区域的八成封顶，图再大就在图区里滚动。
struct PanelLayout: Equatable {
    let size: CGSize
    /// 图片模式才有：原图的点尺寸。图区实际显示多大由窗口此刻的大小决定，装不下就滚动。
    let image: CGSize?

    static let padding: CGFloat = 16
    /// 拖小的下限：头部、一句话总结、一截译文、底部按钮同时在场也还摆得下。
    /// 这个数是量出来的，不是估的：最窄宽度下总结至多三行占 59 点，加行距 69 点，原先的 200 正好不够，
    /// 少了它按钮会被挤出窗外。浮层上能同时出现的块变了，这条线就得重量一次。
    static let minSize = CGSize(width: 320, height: 270)
    /// 文本模式的出厂尺寸，也是图片模式宽度的下限（下方译文和按钮要地方）。
    private static let defaultTextSize = CGSize(width: 440, height: 320)
    /// 图区之外的固定开销：头部 + 分隔线 + 下方完整译文区 + 底部按钮 + 内边距。
    /// 只用来估开场尺寸；开场后图区与译文区怎么分，由视图按窗口实际大小排。
    private static let chromeHeight: CGFloat = 230
    /// 浮层最大占屏幕可见区域的比例——留两成看得见底下的活，工具是配角。
    private static let screenFraction: CGFloat = 0.8
    private static let textSizeKey = "textPanelSize"

    static var text: PanelLayout { PanelLayout(size: textSize, image: nil) }

    /// 用户在文本模式下调好的大小，下次弹出照此开场。
    static var textSize: CGSize {
        get {
            guard let stored = UserDefaults.standard.string(forKey: textSizeKey) else { return defaultTextSize }
            let size = NSSizeFromString(stored)
            return size.width >= minSize.width && size.height >= minSize.height ? size : defaultTextSize
        }
        set { UserDefaults.standard.set(NSStringFromSize(newValue), forKey: textSizeKey) }
    }

    static func image(content: CGSize, screen: CGSize) -> PanelLayout {
        let maxSize = CGSize(
            width: screen.width * screenFraction,
            height: screen.height * screenFraction
        )
        let width = min(max(defaultTextSize.width, content.width + padding * 2), maxSize.width)
        let viewportHeight = min(content.height, max(maxSize.height - chromeHeight, 120))
        return PanelLayout(
            size: CGSize(width: width, height: viewportHeight + chromeHeight),
            image: content
        )
    }

    /// 原尺寸 = 一个图像像素画在一个屏幕物理像素上：Retina 上的截图正好还原成它在屏幕上原本的大小。
    /// 不能直接信 NSImage.size——剪贴板给的 TIFF 不带 DPI，它报的其实是像素数，照着画就大一倍；
    /// 只认位图自己的 pixelsWide/High，再按屏幕缩放折算成点。
    static func naturalSize(of image: NSImage, scale: CGFloat) -> CGSize {
        let pixels = image.representations
            .compactMap { $0 as? NSBitmapImageRep }
            .max { $0.pixelsWide < $1.pixelsWide }
        // 矢量来源（PDF / EPS，如从 Keynote 复制的图形）没有像素，它的 size 本就是点尺寸，直接用
        guard let pixels else { return clamped(image.size) }
        let scale = max(scale, 1)
        return clamped(CGSize(
            width: CGFloat(pixels.pixelsWide) / scale,
            height: CGFloat(pixels.pixelsHigh) / scale
        ))
    }

    private static func clamped(_ size: CGSize) -> CGSize {
        CGSize(width: max(size.width, 1), height: max(size.height, 1))
    }
}

/// 浮层将要（或正在）出现的屏幕：优先鼠标所在屏，其次主屏。
@MainActor
enum PanelScreen {
    static var current: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }
}
