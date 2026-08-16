import SwiftUI

struct TranslationView: View {
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
        .padding(16)
        .frame(width: 440, height: state.displaysSourceImage ? 400 : 320, alignment: .topLeading)
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

    /// 原图即原文：译文像字幕一样盖在图片底部，随流式输出长出来。
    /// 图上最多四行，完整译文仍在下方内容区，可读可复制。
    private func stampedImage(_ image: NSImage) -> some View {
        let fitted = fittedSize(of: image)
        return Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: fitted.width, height: fitted.height)
            .overlay(alignment: .bottom) {
                if !state.translation.isEmpty {
                    Text(state.translation)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(4)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            LinearGradient(
                                stops: [
                                    .init(color: .black.opacity(0), location: 0),
                                    .init(color: .black.opacity(0.78), location: 0.45),
                                ],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1))
            )
    }

    /// 宽度撑满内容区、高度封顶 150，按原图比例反推出实际显示尺寸；
    /// 尺寸算死了，字幕蒙层才不会盖到图外。
    private func fittedSize(of image: NSImage) -> CGSize {
        let aspect = max(image.size.width, 1) / max(image.size.height, 1)
        var width = 408.0
        var height = width / aspect
        if height > 150 {
            height = 150
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
