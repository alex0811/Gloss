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
    /// 剪贴板是图片时保留原图，结果区显示它并把译文盖上；文本翻译则为 nil。
    @Published var sourceImage: NSImage?
    /// 设置页开关：图片翻译是否显示原图，关掉只看译文。默认开。
    @Published var showsSourceImage =
        UserDefaults.standard.object(forKey: AppState.showsSourceImageKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(showsSourceImage, forKey: Self.showsSourceImageKey) }
    }
    @Published var translation = ""
    @Published var status: Status = .idle
    /// 剪贴板出现了浮层尚未处理的新内容——「重新翻译」按钮亮起的依据。
    @Published private(set) var hasNewClipboard = false

    /// 此刻浮层是否按图片模式布局（有原图且开关开着）——视图高度与面板尺寸共用的判定。
    var displaysSourceImage: Bool { sourceImage != nil && showsSourceImage }

    private static let showsSourceImageKey = "showsSourceImage"

    private let panel = PanelController()
    private var streamTask: Task<Void, Never>?
    /// 剪贴板版本号：轮询比对它，比内容哈希便宜也可靠。
    private var lastChangeCount = 0
    private var clipboardWatcher: AnyCancellable?

    private init() {
        KeyboardShortcuts.onKeyUp(for: .translateClipboard) { [weak self] in
            self?.hotkeyPressed()
        }
        lastChangeCount = NSPasteboard.general.changeCount
        clipboardWatcher = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in self?.checkClipboard() }
            }
    }

    /// 只有「面板处理过之后又复制了新东西」才点亮按钮；自己写回的译文不算。
    private func checkClipboard() {
        let count = NSPasteboard.general.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        hasNewClipboard = true
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
        sourceImage = nil
        translation = ""
        hasNewClipboard = false

        switch Clipboard.read() {
        case .text(let text):
            startTranslation(of: text)
        case .image(let image):
            sourceImage = image
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
        // 复制的是译文本身，不算新内容，别把「重新翻译」点亮。
        lastChangeCount = pasteboard.changeCount
    }
}
