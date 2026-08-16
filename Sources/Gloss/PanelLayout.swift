import AppKit

/// 浮层尺寸的唯一事实：视图与 NSPanel 都从这一份读，改一处两处都跟着变。
/// 文本模式固定大小；图片模式跟着原图长、到屏幕可见区域的八成封顶，图再大就在图区里滚动。
struct PanelLayout: Equatable {
    /// 图片模式的图区：content 是原图点尺寸，viewport 是图区实际显示尺寸（装不下 content 就滚动）。
    struct ImageArea: Equatable {
        let content: CGSize
        let viewport: CGSize
    }

    let size: CGSize
    /// 图片模式才有；nil 即文本模式布局。
    let image: ImageArea?

    static let padding: CGFloat = 16
    static let text = PanelLayout(size: CGSize(width: 440, height: 320), image: nil)
    /// 图区之外的固定开销：头部 + 分隔线 + 下方完整译文区 + 底部按钮 + 内边距。
    /// 译文区能屈能伸（maxHeight: .infinity），这个数只调它分到多少，不精确也不破版。
    private static let chromeHeight: CGFloat = 230
    /// 浮层最大占屏幕可见区域的比例——留两成看得见底下的活，工具是配角。
    private static let screenFraction: CGFloat = 0.8

    static func image(content: CGSize, screen: CGSize) -> PanelLayout {
        let maxSize = CGSize(
            width: screen.width * screenFraction,
            height: screen.height * screenFraction
        )
        // 宽不窄于文本模式（下方译文和按钮要地方），高度封顶后余量全给图区
        let width = min(max(text.size.width, content.width + padding * 2), maxSize.width)
        let viewport = CGSize(
            width: min(content.width, width - padding * 2),
            height: min(content.height, max(maxSize.height - chromeHeight, 120))
        )
        return PanelLayout(
            size: CGSize(width: width, height: viewport.height + chromeHeight),
            image: ImageArea(content: content, viewport: viewport)
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
