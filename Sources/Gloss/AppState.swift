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
        case recognizing
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
        streamTask?.cancel()
        sourceText = ""
        translation = ""

        switch Clipboard.read() {
        case .text(let text):
            startTranslation(of: text)
        case .image(let image):
            recognizeThenTranslate(image)
        case .empty:
            status = .failed("剪贴板里没有文本或图片，先复制一段再按快捷键", showSettings: false)
            panel.show()
        }
    }

    private func startTranslation(of text: String) {
        sourceText = text
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

    /// 图片先在本地识别出文字，再交回原有翻译流。
    private func recognizeThenTranslate(_ image: NSImage) {
        status = .recognizing
        panel.show()
        streamTask = Task { [weak self] in
            do {
                let text = try await OCR.recognizeText(in: image)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !Task.isCancelled else { return }
                guard !text.isEmpty else {
                    self?.status = .failed("图片里没识别到文字", showSettings: false)
                    return
                }
                self?.startTranslation(of: text)
            } catch is CancellationError {
                // 主动取消不算失败
            } catch {
                guard !Task.isCancelled else { return }
                self?.status = .failed("识别失败：\(error.localizedDescription)", showSettings: false)
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
