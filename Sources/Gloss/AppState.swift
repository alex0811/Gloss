import AppKit
import Combine
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let translateClipboard = Self(
        "translateClipboard",
        default: .init(.t, modifiers: [.command, .option])
    )
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    enum Status: Equatable {
        case idle
        case streaming
        case done
        case failed(String, showSettings: Bool)
    }

    @Published var sourceText = ""
    @Published var translation = ""
    @Published var status: Status = .idle

    private let panel = PanelController()
    private var streamTask: Task<Void, Never>?

    private init() {
        KeyboardShortcuts.onKeyUp(for: .translateClipboard) { [weak self] in
            self?.hotkeyPressed()
        }
    }

    /// 热键是开关：浮层可见时按下即收起，否则翻译当前剪贴板。
    func hotkeyPressed() {
        if panel.isVisible {
            dismiss()
        } else {
            translateClipboard()
        }
    }

    func translateClipboard() {
        let text = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        streamTask?.cancel()
        sourceText = text
        translation = ""

        guard !text.isEmpty else {
            status = .failed("剪贴板里没有文本，先复制一段再按快捷键", showSettings: false)
            panel.show()
            return
        }

        status = .streaming
        panel.show()
        streamTask = Task { [weak self] in
            do {
                for try await chunk in Translator.translate(text) {
                    guard !Task.isCancelled else { return }
                    self?.translation += chunk
                }
                guard !Task.isCancelled else { return }
                self?.status = .done
            } catch is CancellationError {
                // 主动取消不算失败
            } catch {
                guard !Task.isCancelled else { return }
                self?.status = .failed(error.localizedDescription, showSettings: true)
            }
        }
    }

    func dismiss() {
        streamTask?.cancel()
        panel.hide()
    }

    func copyTranslation() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(translation, forType: .string)
    }
}
