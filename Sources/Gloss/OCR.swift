import AppKit
import CoreImage
import Vision

/// 识别出的一行文字。box 是归一化矩形（0…1，原点在左上），乘上显示尺寸即得它在原图上的位置。
struct RecognizedLine: Identifiable {
    let id: Int
    let text: String
    let box: CGRect
    /// 这一行底下的纸偏深还是偏浅——玻璃的洗色与墨色跟它走。
    var isDarkBackground = false
    /// 译文按行号回填到这里，由视图叠回 box。
    var translation = ""
}

/// 识别的全部产出：逐行文字与位置，外加一块磨去墨迹只剩纸色的「毛玻璃底板」。
/// 底板与识别框出自同一份位图，译文玻璃才能与原文严丝合缝；CI 渲染失败时为 nil，视图退回素色。
struct Recognition {
    let lines: [RecognizedLine]
    let plate: NSImage?
}

/// 图片文字识别：Apple Vision，本地执行，零权限零费用。
/// 截图里的英文菜单、微信聊天记录、网页长图，复制后直接走原有翻译流。
enum OCR {
    static func recognize(in image: NSImage) async throws -> Recognition {
        try await Task.detached(priority: .userInitiated) {
            try recognize(image)
        }.value
    }

    private static func recognize(_ image: NSImage) throws -> Recognition {
        guard let cgImage = cgImage(from: image) else {
            throw APIError(message: "剪贴板里的图片无法读取")
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]

        let handler = VNImageRequestHandler(cgImage: cgImage)
        try handler.perform([request])

        // Vision 坐标系原点在左下角：先按行（y 从上往下），行内再从左到右；行号由此定死
        let observations = (request.results ?? []).sorted { a, b in
            let (ab, bb) = (a.boundingBox, b.boundingBox)
            if abs(ab.minY - bb.minY) > 0.01 { return ab.minY > bb.minY }
            return ab.minX < bb.minX
        }
        // 先滤掉认空的行，再编号：行号是发给模型的钥匙，也是回填时的序号，中间不留缺口
        let lines = observations.compactMap { observation -> (String, CGRect)? in
            let text = observation.topCandidates(1).first?.string
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { return nil }
            let bb = observation.boundingBox
            return (text, CGRect(x: bb.minX, y: 1 - bb.maxY, width: bb.width, height: bb.height))
        }
        .enumerated()
        .map { offset, line in
            RecognizedLine(
                id: offset + 1, text: line.0, box: line.1,
                isDarkBackground: isDark(line.1, in: cgImage)
            )
        }
        return Recognition(
            lines: lines,
            plate: lines.isEmpty ? nil : plate(from: cgImage, boxes: lines.map(\.box))
        )
    }

    /// 一行底下的纸是深是浅：识别框裁下来缩成一小把灰度像素取中位数。
    /// 中位数不看墨迹多少——粗体大字也占不过半行，答案就是纸色本身；均值会被浓墨拖偏。
    private static func isDark(_ box: CGRect, in cgImage: CGImage) -> Bool {
        let pixelBox = CGRect(
            x: box.minX * CGFloat(cgImage.width),
            y: box.minY * CGFloat(cgImage.height),
            width: box.width * CGFloat(cgImage.width),
            height: box.height * CGFloat(cgImage.height)
        ).integral
        guard pixelBox.width >= 1, pixelBox.height >= 1,
              let crop = cgImage.cropping(to: pixelBox) else { return false }
        let width = 24, height = 6
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            // 透明当白纸：浮层底色是浅的
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return false }
        return pixels.sorted()[pixels.count / 2] < 128
    }

    private static let ciContext = CIContext()

    /// 毛玻璃底板：整图高斯模糊，磨掉墨迹、留下纸色。半径跟着最高的行走——
    /// 大标题也要糊到认不出字形；多糊无妨（纸还是纸），糊不够译文底下就漏出原文的鬼影。
    private static func plate(from cgImage: CGImage, boxes: [CGRect]) -> NSImage? {
        let tallest = boxes.map(\.height).max() ?? 0
        // 0.6 倍行高起字形才彻底化开；上限防着巨幅标题把整张纸糊成汤
        let radius = min(max(tallest * CGFloat(cgImage.height) * 0.6, 12), 60)
        let extent = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        // clamp 再裁回：不然边缘会往透明里糊出一圈黑晕
        let blurred = CIImage(cgImage: cgImage)
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: extent)
        // 渲染一次、落成自有位图：CI 的 CGImage 惰性求值，像素到绘制时才算；
        // 底板会被反复缩放取景，落成确定的像素，之后的绘制就与 CI 无涉
        guard let bitmap = CGContext(
            data: nil, width: cgImage.width, height: cgImage.height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let buffer = bitmap.data else { return nil }
        ciContext.render(
            blurred, toBitmap: buffer, rowBytes: bitmap.bytesPerRow,
            bounds: extent, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        guard let output = bitmap.makeImage() else { return nil }
        return NSImage(cgImage: output, size: .zero)
    }

    /// NSImage 可能是位图也可能是 PDF 等矢量来源（如从 Keynote 复制的图形），
    /// 位图直接取 CGImage，矢量按像素尺寸栅格化后再识别。
    private static func cgImage(from image: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        if let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
            return cg
        }
        let scale: CGFloat = 2
        let width = max(1, Int(image.size.width * scale))
        let height = max(1, Int(image.size.height * scale))
        guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }
}
