import AppKit
import Vision

/// 图片文字识别：Apple Vision，本地执行，零权限零费用。
/// 截图里的英文菜单、微信聊天记录、网页长图，复制后直接走原有翻译流。
enum OCR {
    static func recognizeText(in image: NSImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try recognize(image)
        }.value
    }

    private static func recognize(_ image: NSImage) throws -> String {
        guard let cgImage = cgImage(from: image) else {
            throw APIError(message: "剪贴板里的图片无法读取")
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]

        let handler = VNImageRequestHandler(cgImage: cgImage)
        try handler.perform([request])

        // Vision 坐标系原点在左下角：先按行（y 从上往下），行内再从左到右
        let observations = (request.results ?? []).sorted { a, b in
            let (ab, bb) = (a.boundingBox, b.boundingBox)
            if abs(ab.minY - bb.minY) > 0.01 { return ab.minY > bb.minY }
            return ab.minX < bb.minX
        }
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
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
