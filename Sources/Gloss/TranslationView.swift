import SwiftUI

/// 尺寸的唯一事实在 PanelLayout：视图与 NSPanel 都读 AppState.layout，这里不自己算大小。
struct TranslationView: View {
    @ObservedObject var state = AppState.shared
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let image = state.sourceImage, let area = state.layout.image {
                stampedImage(image, in: area)
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
        .padding(PanelLayout.padding)
        .frame(
            width: state.layout.size.width,
            height: state.layout.size.height,
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

    /// 原图即原文：按原尺寸铺开（不缩不放，就是它在屏幕上原本的大小），译文按识别位置逐行叠回图上，
    /// 随流式输出一行行亮起来，恰是行间注的样子。浮层跟着图撑大；图大过屏幕封顶时才在图区里滚动。
    /// 完整译文仍在下方内容区，可读可复制。
    private func stampedImage(_ image: NSImage, in area: PanelLayout.ImageArea) -> some View {
        // 只有真的装不下的那一轴才开滚动，装得下的一轴不留橡皮筋回弹
        var axes: Axis.Set = []
        if area.content.width > area.viewport.width { axes.insert(.horizontal) }
        if area.content.height > area.viewport.height { axes.insert(.vertical) }

        return ScrollView(axes) {
            ZStack(alignment: .topLeading) {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: area.content.width, height: area.content.height)
                ForEach(state.imageLines) { line in
                    glossLine(line, in: area.content)
                }
            }
            .frame(width: area.content.width, height: area.content.height, alignment: .topLeading)
        }
        // 换一张图就回到左上角：浮层是常驻的，不重置会带着上一张的滚动位置开场
        .id(ObjectIdentifier(image))
        .frame(width: area.viewport.width, height: area.viewport.height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1))
        )
    }

    /// 一行注一行：卡片高度锚死在识别框上，只向右生长——中译英再长也压不到下一行，
    /// 宽过图就缩字号、再不够就截断（完整译文下方一字不少），绝不让两行糊成一团黑。
    private func glossLine(_ line: RecognizedLine, in imageSize: CGSize) -> some View {
        let box = CGRect(
            x: line.box.minX * imageSize.width,
            y: line.box.minY * imageSize.height,
            width: line.box.width * imageSize.width,
            height: line.box.height * imageSize.height
        )
        let height = max(box.height, 13)
        return HStack(spacing: 0) {
            Text(line.translation)
                // 字号跟着识别框走：原尺寸下这就是原文自己的大小，译文才像贴着原文的注
                .font(.system(size: min(max(height * 0.7, 9), 24), weight: .medium))
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
        .frame(width: max(imageSize.width - box.minX, 1), alignment: .leading)
        // 这一行的译文一到就亮起来，没到的行不留黑块
        .opacity(line.translation.isEmpty ? 0 : 1)
        .animation(.easeOut(duration: 0.18), value: line.translation.isEmpty)
        .offset(x: box.minX, y: box.midY - height / 2)
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
