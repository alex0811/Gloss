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
        /// 译文已完整，正在压那一句话。`.done` 才是真的全都完了。
        case summarizing
        case done
        case failed(String, showSettings: Bool)
    }

    @Published var sourceText = ""
    /// 剪贴板是图片时保留原图，结果区显示它并把译文盖上；文本翻译则为 nil。
    @Published var sourceImage: NSImage? {
        didSet { updateLayout() }
    }
    /// 设置页开关：图片翻译是否显示原图，关掉只看译文。默认开。
    @Published var showsSourceImage =
        UserDefaults.standard.object(forKey: AppState.showsSourceImageKey) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showsSourceImage, forKey: Self.showsSourceImageKey)
            updateLayout()
        }
    }
    /// 设置页开关：长译文译完后，再请模型压一句话摆在译文上方。默认开。
    @Published var summarizes =
        UserDefaults.standard.object(forKey: AppState.summarizesKey) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(summarizes, forKey: Self.summarizesKey)
            summarizesChanged()
        }
    }
    /// 译成什么语言（默认见 TranslationPref）。设置页写它，翻译从 TranslationPref 读。
    @Published var targetLanguage = TranslationPref.target {
        didSet {
            guard targetLanguage != oldValue else { return }
            TranslationPref.target = targetLanguage
            targetLanguageChanged()
        }
    }
    /// 用户写给译者的偏好。即存即用，但不当场重翻：逐字在改，每敲一键重发一次请求不值当。
    @Published var translationNotes = TranslationPref.notes {
        didSet { TranslationPref.notes = translationNotes }
    }
    @Published var translation = ""
    /// 一句话总结。译文流完才有——压半截译文压出来的话不作数。
    @Published private(set) var summary = ""
    /// 总结失败只落在总结这一行：注写砸了不该把译好的正文一起换成红字。
    @Published private(set) var summaryFailure: String?
    /// 本地预检判定这段原文本就是目标语言，这一次没发请求——译文栏里摆的就是原文。
    /// 浮层得说出这件事，不然「怎么一点没变」只能靠猜（气质准则「只 gloss，不 gloss over」）。
    @Published private(set) var isPassthrough = false
    /// 图片模式下的识别行；译文按行号回填进来，视图把每行叠回原图的识别位置。
    @Published private(set) var imageLines: [RecognizedLine] = []
    /// 原图磨去墨迹只剩纸色的毛玻璃底板：译文行的玻璃从这上面对位取景。与 imageLines 同源同生命周期。
    @Published private(set) var frostedPlate: NSImage?
    @Published var status: Status = .idle
    /// 剪贴板出现了浮层尚未处理的新内容——「重新翻译」按钮亮起的依据。
    @Published private(set) var hasNewClipboard = false
    /// 浮层置顶：浮在所有窗之上，不被切过去的 App 盖住。只管这一次弹出：浮层收起就取消，下次弹出照旧是普通窗。
    @Published var isPinned = false {
        didSet { panel.pinnedChanged() }
    }
    /// 浮层此刻的布局：视图和面板都读它。跟着 sourceImage / showsSourceImage 变，不单独手改。
    @Published private(set) var layout: PanelLayout = .text

    private static let showsSourceImageKey = "showsSourceImage"
    private static let summarizesKey = "summarizes"

    private let panel = PanelController()
    /// 浮层此刻正在进行的那一次请求：翻译，或翻译之后接着跑的总结。
    /// 两者先后不重叠，所以只有一个——要掐就是掐它，不必分头记两份。
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

    /// 布局跟着「有没有图、开关开没开」走：图片模式按原图撑大浮层，其余回到文本模式定尺寸。
    private func updateLayout() {
        guard let image = sourceImage, showsSourceImage else {
            layout = .text
            return
        }
        let screen = panel.targetScreen
        layout = .image(
            content: PanelLayout.naturalSize(of: image, scale: screen?.backingScaleFactor ?? 2),
            screen: screen?.visibleFrame.size ?? CGSize(width: 1280, height: 800)
        )
    }

    /// 设置里换了目标语言：眼下这份原文就地重翻，不必重新复制、也不必再按一次按钮。
    /// 浮层没开着就什么都不做——下次热键自然用新语言。
    private func targetLanguageChanged() {
        guard panel.isVisible else { return }
        retranslateCurrent()
    }

    /// 开关当场生效，不必重翻：眼下这份译文该有的总结补上，不该有的立刻收走。
    /// 浮层没开着就什么都不做——没人在看的译文不值得多发一次请求。
    private func summarizesChanged() {
        guard panel.isVisible else { return }
        guard summarizes else {
            if status == .summarizing {
                streamTask?.cancel()
                status = .done
            }
            summary = ""
            summaryFailure = nil
            return
        }
        // 译文还在流就什么都不做：它流完自然接着总结。
        // 这时候另起一个任务会把 streamTask 指走，正在流的译文就此失去被掐的把手。
        guard status == .done else { return }
        streamTask = Task { [weak self] in await self?.summarize() }
    }

    /// 重翻眼下这份原文——不是剪贴板此刻的内容（那可能早换了）。
    /// 正因如此不碰 hasNewClipboard / lastChangeCount：等着被翻的新剪贴板还等着，按钮该亮照亮。
    private func retranslateCurrent() {
        if !imageLines.isEmpty {
            // 图片连识别都不必重跑：行还在，清掉旧译文换门语言再发一次即可
            let lines = imageLines.map { line -> RecognizedLine in
                var line = line
                line.translation = ""
                return line
            }
            imageLines = lines
            restream { self.translateLines(lines) }
        } else if !sourceText.isEmpty {
            let text = sourceText
            restream { self.translateText(text) }
        }
        // 识别还没出结果时两边都空：什么都不做——那次请求发出时自会用上新语言
    }

    /// 掐掉正在流的那次，清空译文，从头再走一遍入口。
    /// 重来一遍走的是入口而非 `begin`：换了门语言，本地预检的答案也可能跟着翻面
    /// （原文是中文，目标从中文改成英文，这一次就该真发请求了）。
    private func restream(_ start: @MainActor () -> Void) {
        streamTask?.cancel()
        clearResult()
        start()
    }

    /// 文本这一路的唯一入口：本地预检说整段已经是目标语言，就地把原文交回去，一次请求都不发。
    /// 判定挡在 `begin` 外面，不是挡在请求前面——不走那条路，「译完接着总结」的尾巴也就够不着：
    /// 总结的对象是译文，而这里根本没有译文（`Summary.prompt` 开口就说「下面是一段译文」）。
    private func translateText(_ text: String) {
        guard !Precheck.isAlreadyTarget(text) else {
            isPassthrough = true
            translation = text
            present(.done)
            return
        }
        begin(.streaming) { try await self.streamText(text) }
    }

    /// 图片这一路的入口。识别出的行照旧整段发出：预检只管文字模式。
    private func translateLines(_ lines: [RecognizedLine]) {
        begin(.streaming) { try await self.streamLines(lines) }
    }

    /// 译文和它的那句总结是同一份结果，换就一起换：只清一半，浮层上就成了新原文配旧总结。
    private func clearResult() {
        translation = ""
        summary = ""
        summaryFailure = nil
        isPassthrough = false
    }

    /// 只有「面板处理过之后又复制了新东西」才点亮按钮；自己写回的译文不算。
    private func checkClipboard() {
        let count = NSPasteboard.general.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        hasNewClipboard = true
    }

    /// 热键是开关：浮层露在外面时按下即收起。
    /// 没露出来时：没显示，或被别的窗整个盖住却有新剪贴板，就翻译；被盖住而剪贴板没变，只把它亮出来，不重发请求。
    func hotkeyPressed() {
        if panel.isExposed {
            dismiss()
        } else if panel.isVisible && !hasNewClipboard {
            panel.show()
        } else {
            translateClipboard()
        }
    }

    func translateClipboard() {
        streamTask?.cancel()
        sourceText = ""
        sourceImage = nil
        imageLines = []
        frostedPlate = nil
        clearResult()
        hasNewClipboard = false
        // 热键快过 0.5 秒的轮询时，这份剪贴板已经翻过了——不认领它，下一拍就会误亮「重新翻译」。
        lastChangeCount = NSPasteboard.general.changeCount

        switch Clipboard.read() {
        case .text(let text):
            sourceText = text
            translateText(text)
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
                return
            } catch let failure as Failure {
                guard !Task.isCancelled else { return }
                self?.status = .failed(failure.message, showSettings: failure.showSettings)
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.status = .failed(error.localizedDescription, showSettings: true)
                return
            }
            // 译文齐了才轮到总结：同一个任务往下走，掐译文就等于连总结一起掐了
            await self?.summarize()
        }
    }

    /// 总结只从这里开始：译文流完顺势往下走，或设置里刚打开开关时补一次。
    /// 该不该总结的判据全写在这道 guard 上，两个入口共认这一份。
    /// 不借道 `begin`：总结失败只该落在总结那一行——正文已经译好了，不能被一句注的失手顶掉。
    private func summarize() async {
        guard summarizes, status == .done, summary.isEmpty, summaryFailure == nil,
              // 预检放行的那一次没有译文，摆着的是原文：压它等于让 prompt 里「下面是一段译文」说了假话
              !isPassthrough,
              Summary.deserves(translation)
        else { return }
        status = .summarizing
        do {
            for try await chunk in Translator.summarize(translation) {
                guard !Task.isCancelled else { return }
                // 顺手掐头去尾：模型爱在前面带个空行，带着它这一句就先空一行才开始
                summary = (summary + chunk).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            summaryFailure = "总结失败：\(error.localizedDescription)"
        }
        guard !Task.isCancelled else { return }
        status = .done
    }

    private func streamText(_ text: String) async throws {
        for try await chunk in Translator.translate(text) {
            guard !Task.isCancelled else { return }
            translation += chunk
        }
    }

    /// 图片先在本地识别出每行文字和位置，再按行号整段翻译，译文逐行叠回原图。
    private func recognizeThenStream(_ image: NSImage) async throws {
        let recognition: Recognition
        do {
            recognition = try await OCR.recognize(in: image)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // 识别是本地的事，与服务商配置无关，别把用户往设置页支
            throw Failure(message: "识别失败：\(error.localizedDescription)", showSettings: false)
        }
        guard !Task.isCancelled else { return }
        guard !recognition.lines.isEmpty else {
            throw Failure(message: "图片里没识别到文字", showSettings: false)
        }
        imageLines = recognition.lines
        frostedPlate = recognition.plate
        status = .streaming
        try await streamLines(recognition.lines)
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
        isPinned = false
    }

    func copyTranslation() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(translation, forType: .string)
        // 复制的是译文本身，不算新内容，别把「重新翻译」点亮。
        lastChangeCount = pasteboard.changeCount
    }
}
