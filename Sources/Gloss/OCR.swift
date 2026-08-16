import AppKit
import Vision

/// 识别出的一行文字。box 是归一化矩形（0…1，原点在左上），乘上显示尺寸即得它在原图上的位置。
struct RecognizedLine: Identifiable {
    let id: Int
    let text: String
    let box: CGRect
    /// 译文按行号回填到这里，由视图叠回 box。
    var translation = ""
}

/// 图片文字识别：Apple Vision，本地执行，零权限零费用。
/// 截图里的英文菜单、微信聊天记录、网页长图，复制后直接走原有翻译流。
enum OCR {
    static func recognizeLines(in image: NSImage) async throws -> [RecognizedLine] {
        try await Task.detached(priority: .userInitiated) {
            try recognize(image)
        }.value
    }

    private static func recognize(_ image: NSImage) throws -> [RecognizedLine] {
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
        return observations.compactMap { observation -> (String, CGRect)? in
            let text = observation.topCandidates(1).first?.string
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { return nil }
            let bb = observation.boundingBox
            return (text, CGRect(x: bb.minX, y: 1 - bb.maxY, width: bb.width, height: bb.height))
        }
        .enumerated()
        .map { RecognizedLine(id: $0.offset + 1, text: $0.element.0, box: $0.element.1) }
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
