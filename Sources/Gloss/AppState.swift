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
    /// 图片模式下的识别行；译文按行号回填进来，视图把每行叠回原图的识别位置。
    @Published private(set) var imageLines: [RecognizedLine] = []
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
        imageLines = []
        translation = ""
        hasNewClipboard = false
        // 热键快过 0.5 秒的轮询时，这份剪贴板已经翻过了——不认领它，下一拍就会误亮「重新翻译」。
        lastChangeCount = NSPasteboard.general.changeCount

        switch Clipboard.read() {
        case .text(let text):
            sourceText = text
            begin(.streaming) { try await self.streamText(text) }
        case .image(let image):
            sourceImage = image
            begin(.recognizing) { try await self.recognizeThenStream(image) }
        case .empty:
            present(.failed("剪贴板里没有文本或图片，先复制一段再按快捷键", showSettings: false))
        }
    }

    /// 出错时说什么、要不要指路去设置，由知情的那一方抛出来定，不留给各处 catch 各猜一份。
    private struct Failure: Error {
        let message: String
        let showSettings: Bool
    }

    /// 面板与状态一起亮相：状态变了才值得弹面板，两件事不分家。
    private func present(_ status: Status) {
        self.status = status
        panel.show()
    }

    /// 所有翻译共走这一条：面板归它弹、任务归它管，取消语义与失败呈现只在这里收口。
    /// 文本、图片各自只管「文字怎么变成状态」，控制流不再各抄一份。
    private func begin(_ status: Status, _ work: @escaping @MainActor () async throws -> Void) {
        present(status)
        streamTask = Task { [weak self] in
            do {
                try await work()
                guard !Task.isCancelled else { return }
                self?.status = .done
            } catch is CancellationError {
                // 主动取消不算失败
            } catch let failure as Failure {
                guard !Task.isCancelled else { return }
                self?.status = .failed(failure.message, showSettings: failure.showSettings)
            } catch {
                guard !Task.isCancelled else { return }
                self?.status = .failed(error.localizedDescription, showSettings: true)
            }
        }
    }

    private func streamText(_ text: String) async throws {
        for try await chunk in Translator.translate(text) {
            guard !Task.isCancelled else { return }
            translation += chunk
        }
    }

    /// 图片先在本地识别出每行文字和位置，再按行号整段翻译，译文逐行叠回原图。
    private func recognizeThenStream(_ image: NSImage) async throws {
        let lines: [RecognizedLine]
        do {
            lines = try await OCR.recognizeLines(in: image)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // 识别是本地的事，与服务商配置无关，别把用户往设置页支
            throw Failure(message: "识别失败：\(error.localizedDescription)", showSettings: false)
        }
        guard !Task.isCancelled else { return }
        guard !lines.isEmpty else {
            throw Failure(message: "图片里没识别到文字", showSettings: false)
        }
        imageLines = lines
        status = .streaming
        try await streamLines(lines)
    }

    /// 各行编号后整段发出——一次请求保住全文语境，译文流回来按行号抠出，位置仍能对回每一行。
    private func streamLines(_ lines: [RecognizedLine]) async throws {
        var buffer = ""
        for try await chunk in Translator.translate(LineFormat.encode(lines), prompt: LineFormat.prompt) {
            guard !Task.isCancelled else { return }
            buffer += chunk
            apply(buffer, to: lines)
        }
        guard !Task.isCancelled else { return }
        apply(buffer, to: lines, final: true)
    }

    /// 下方内容区永远是完整译文（只剥掉行号，模型多说的一个字不吞）；
    /// 图上只叠对得上号的行——抠不出行号就不乱叠，宁可图上先空着。
    private func apply(_ buffer: String, to lines: [RecognizedLine], final: Bool = false) {
        translation = LineFormat.strip(buffer)
        let byNumber = LineFormat.decode(buffer, count: lines.count, final: final)
        guard !byNumber.isEmpty else { return }
        var updated = lines
        for (number, text) in byNumber {
            if let index = updated.firstIndex(where: { $0.id == number }) {
                updated[index].translation = text
            }
        }
        imageLines = updated
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
