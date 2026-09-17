// 合成 README 题头：Design/Banner-bg.png（生成的底图）正中叠上 Design/AppIcon.svg 渲染的图标。
// 图标走 WebKit 渲染，与 render-icon.swift 同一条路径，README 上的图标和 App 图标是同一个形状。
// 用法：swift Scripts/render-banner.swift <底图 png> <svg> <输出 png>
import AppKit
import WebKit

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    FileHandle.standardError.write("用法：render-banner.swift <底图 png> <svg> <输出 png>\n".data(using: .utf8)!)
    exit(2)
}
let bgURL = URL(fileURLWithPath: arguments[1])
let svgURL = URL(fileURLWithPath: arguments[2])
let outURL = URL(fileURLWithPath: arguments[3])

/// 底图裁切区（像素，原点左上）与图标边长。底图光晕已在正中，取全幅。
let crop = CGRect(x: 0, y: 0, width: 2120, height: 742)
let iconSide: CGFloat = 340

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("render-banner: \(message)\n".data(using: .utf8)!)
    exit(1)
}

final class Renderer: NSObject, WKNavigationDelegate {
    let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 1024))
    var onMaster: ((NSImage) -> Void)?

    func start(svg: String) {
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = self
        webView.loadHTMLString("""
        <html><body style="margin:0;background:transparent">
        <div style="width:1024px;height:1024px">\(svg)</div>
        </body></html>
        """, baseURL: nil)
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

func compose(master: NSImage) -> Data {
    guard let bgData = try? Data(contentsOf: bgURL), let bg = NSBitmapImageRep(data: bgData) else { fail("读不到底图 \(bgURL.path)") }
    let width = Int(crop.width), height = Int(crop.height)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fail("无法创建位图") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    // 底图：把裁切区画满画布（bitmap 坐标原点左下，from 的 y 要翻转）
    let bgHeight = CGFloat(bg.pixelsHigh)
    let from = NSRect(x: crop.minX, y: bgHeight - crop.maxY, width: crop.width, height: crop.height)
    bg.draw(in: NSRect(x: 0, y: 0, width: crop.width, height: crop.height), from: from,
            operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
    // 图标：居中，投影比 App 图标略深，浮在光晕上
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
    shadow.shadowOffset = NSSize(width: 0, height: -iconSide * 0.04)
    shadow.shadowBlurRadius = iconSide * 0.08
    shadow.set()
    master.draw(in: NSRect(x: (crop.width - iconSide) / 2, y: (crop.height - iconSide) / 2, width: iconSide, height: iconSide))
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else { fail("PNG 编码失败") }
    return data
}

guard let svg = try? String(contentsOf: svgURL, encoding: .utf8) else { fail("读不到 \(svgURL.path)") }
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let renderer = Renderer()
renderer.onMaster = { master in
    do { try compose(master: master).write(to: outURL) } catch { fail("写文件失败：\(error.localizedDescription)") }
    exit(0)
}
renderer.start(svg: svg)
app.run()
