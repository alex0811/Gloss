import SwiftUI

struct TranslationView: View {
    @ObservedObject var state = AppState.shared
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if !state.sourceText.isEmpty {
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
        .frame(width: 440, height: 320, alignment: .topLeading)
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
