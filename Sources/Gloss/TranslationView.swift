import SwiftUI

struct TranslationView: View {
    /// 浮层尺寸的唯一事实：视图与 NSPanel 共用这一份，改一处两处都跟着变。
    enum Metrics {
        static let width: CGFloat = 440
        static let padding: CGFloat = 16
        /// 图片模式要同时容下原图、叠在图上的译文和下方全文，比纯文本高一截。
        static let imageHeight: CGFloat = 470
        static let textHeight: CGFloat = 320
        /// 原图在浮层里最高占这么多，余下的高度留给下方完整译文。
        static let imageMaxHeight: CGFloat = 240

        static var contentWidth: CGFloat { width - padding * 2 }
        static func height(withImage: Bool) -> CGFloat { withImage ? imageHeight : textHeight }
        static func size(withImage: Bool) -> CGSize {
            CGSize(width: width, height: height(withImage: withImage))
        }
    }

    @ObservedObject var state = AppState.shared
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let image = state.sourceImage, state.showsSourceImage {
                stampedImage(image)
                Divider()
            } else if state.sourceImage == nil, !state.sourceText.isEmpty {
                Text(state.sourceText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                Divider()
            }
            content
            footer
        }
        .padding(Metrics.padding)
        .frame(
            width: Metrics.width,
            height: Metrics.height(withImage: state.displaysSourceImage),
            alignment: .topLeading
        )
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1))
        )
    }

    /// 金色注线即 logo。
    private var header: some View {
        HStack {
            Capsule()
                .fill(LinearGradient(
                    colors: [Color(red: 1.0, green: 0.886, blue: 0.62),
                             Color(red: 0.949, green: 0.659, blue: 0.231)],
                    startPoint: .leading, endPoint: .trailing))
                .frame(width: 22, height: 5)
            Spacer()
            Button {
                AppState.shared.dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    /// 原图即原文：译文按识别位置逐行叠回图上，随流式输出一行行亮起来，恰是行间注的样子。
    /// 完整译文仍在下方内容区，可读可复制。
    private func stampedImage(_ image: NSImage) -> some View {
        let fitted = fittedSize(of: image)
        return ZStack(alignment: .topLeading) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: fitted.width, height: fitted.height)
            ForEach(state.imageLines) { line in
                glossLine(line, in: fitted)
            }
        }
        .frame(width: fitted.width, height: fitted.height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1))
        )
    }

    /// 一行注一行：卡片高度锚死在识别框上，只向右生长——中译英再长也压不到下一行，
    /// 宽过图就缩字号、再不够就截断（完整译文下方一字不少），绝不让两行糊成一团黑。
    private func glossLine(_ line: RecognizedLine, in fitted: CGSize) -> some View {
        let box = CGRect(
            x: line.box.minX * fitted.width,
            y: line.box.minY * fitted.height,
            width: line.box.width * fitted.width,
            height: line.box.height * fitted.height
        )
        let height = max(box.height, 13)
        return HStack(spacing: 0) {
            Text(line.translation)
                .font(.system(size: min(max(height * 0.7, 9), 14), weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .truncationMode(.tail)
                .padding(.horizontal, 4)
                .frame(height: height)
                .background(
                    Color.black.opacity(0.8),
                    in: RoundedRectangle(cornerRadius: 3, style: .continuous)
                )
            Spacer(minLength: 0)
        }
        .frame(width: max(fitted.width - box.minX, 1), alignment: .leading)
        // 这一行的译文一到就亮起来，没到的行不留黑块
        .opacity(line.translation.isEmpty ? 0 : 1)
        .animation(.easeOut(duration: 0.18), value: line.translation.isEmpty)
        .offset(x: box.minX, y: box.midY - height / 2)
    }

    /// 宽度撑满内容区、高度封顶，按原图比例反推出实际显示尺寸；
    /// 尺寸算死了，叠在图上的译文才落得准、跑不出图外。
    private func fittedSize(of image: NSImage) -> CGSize {
        let aspect = max(image.size.width, 1) / max(image.size.height, 1)
        var width = Metrics.contentWidth
        var height = width / aspect
        if height > Metrics.imageMaxHeight {
            height = Metrics.imageMaxHeight
            width = height * aspect
        }
        return CGSize(width: width, height: height)
    }

    private var content: some View {
        ScrollView {
            Group {
                if case .failed(let message, _) = state.status {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                } else {
                    Text(state.translation)
                        .font(.system(size: 14))
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            switch state.status {
            case .recognizing:
                ProgressView()
                    .controlSize(.small)
                Text("识别图片文字…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .streaming:
                ProgressView()
                    .controlSize(.small)
                Text("翻译中…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .failed(_, let showSettings):
                if showSettings {
                    Button("打开设置") { SettingsWindowController.shared.show() }
                        .controlSize(.small)
                }
            case .done, .idle:
                EmptyView()
            }
            Spacer()
            Button {
                state.translateClipboard()
            } label: {
                Label("重新翻译", systemImage: "arrow.triangle.2.circlepath")
            }
            .controlSize(.small)
            .disabled(!state.hasNewClipboard)
            Button(copied ? "已复制" : "复制译文") {
                AppState.shared.copyTranslation()
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.2))
                    copied = false
                }
            }
            .controlSize(.small)
            .disabled(state.translation.isEmpty || copied)
        }
    }
}
