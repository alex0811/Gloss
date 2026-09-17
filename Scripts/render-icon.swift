// 从 Design/AppIcon.svg 生成 AppIcon.icns：svg 是形状唯一来源，icns 每次打包现生成，不进仓库。
// 渲染交给 WebKit：它和 GitHub 上看 README 时渲染这张 svg 的是同一类引擎，发光模糊也最忠实
// （CoreSVG 的 feGaussianBlur 偏弱）。排版按 Apple macOS 图标模板：1024 画布里图标主体 824、
// 四周留 100 给投影；svg 自带的 229/1024 圆角缩到 824 恰是模板的约 185。
// 用法：swift Scripts/render-icon.swift <svg> <输出 .icns>
import AppKit
import WebKit

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write("用法：render-icon.swift <svg> <输出 .icns>\n".data(using: .utf8)!)
    exit(2)
}
let svgURL = URL(fileURLWithPath: arguments[1])
let icnsURL = URL(fileURLWithPath: arguments[2])

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("render-icon: \(message)\n".data(using: .utf8)!)
    exit(1)
}

final class Renderer: NSObject, WKNavigationDelegate {
    let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 1024))
    var onMaster: ((NSImage) -> Void)?

    func start(svg: String) {
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = self
        let html = """
        <html><body style="margin:0;background:transparent">
        <div style="width:1024px;height:1024px">\(svg)</div>
        </body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let config = WKSnapshotConfiguration()
        config.rect = NSRect(x: 0, y: 0, width: 1024, height: 1024)
        webView.takeSnapshot(with: config) { image, error in
            guard let image else { fail("快照失败：\(error?.localizedDescription ?? "未知错误")") }
            self.onMaster?(image)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail("加载失败：\(error.localizedDescription)")
    }
}

/// 按模板把主体放进 size×size 画布：主体占 824/1024，带一层柔和投影。
func iconPNG(master: NSImage, size: Int) -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fail("无法创建 \(size)px 位图") }
    let scale = CGFloat(size) / 1024
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -10 * scale)
    shadow.shadowBlurRadius = 20 * scale
    shadow.set()
    master.draw(in: NSRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale))
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else { fail("PNG 编码失败") }
    return data
}

guard let svg = try? String(contentsOf: svgURL, encoding: .utf8) else { fail("读不到 \(svgURL.path)") }

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let renderer = Renderer()
renderer.onMaster = { master in
    let fm = FileManager.default
    let iconset = fm.temporaryDirectory.appendingPathComponent("Gloss-\(UUID().uuidString).iconset")
    do {
        try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            try iconPNG(master: master, size: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
            try iconPNG(master: master, size: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
        }
    } catch {
        fail("写 iconset 失败：\(error.localizedDescription)")
    }
    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["-c", "icns", iconset.path, "-o", icnsURL.path]
    do { try iconutil.run() } catch { fail("iconutil 启动失败：\(error.localizedDescription)") }
    iconutil.waitUntilExit()
    try? fm.removeItem(at: iconset)
    guard iconutil.terminationStatus == 0 else { fail("iconutil 退出码 \(iconutil.terminationStatus)") }
    exit(0)
}
renderer.start(svg: svg)
app.run()
