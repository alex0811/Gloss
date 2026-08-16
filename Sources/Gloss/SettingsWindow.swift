import AppKit
import SwiftUI
import KeyboardShortcuts

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Gloss 设置"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView())
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @AppStorage(ConfigKey.baseURL) private var baseURL = ""
    @AppStorage(ConfigKey.model) private var model = ""
    @State private var apiKey = AppConfig.apiKey
    @State private var keyJustSaved = false
    @State private var models: [String] = []
    @State private var isLoadingModels = false
    @State private var modelsError: String?

    var body: some View {
        Form {
            Section("服务（OpenAI 兼容协议）") {
                TextField("Base URL", text: $baseURL, prompt: Text("如 https://api.deepseek.com"))
                HStack {
                    SecureField("API Key", text: $apiKey, prompt: Text("sk-…"))
                    Button(keyJustSaved ? "已存入 Keychain" : "保存") {
                        keyJustSaved = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            keyJustSaved = false
                        }
                        refreshModels()
                    }
                    .disabled(keyJustSaved)
                }
                modelRow
            }
            Section("快捷键") {
                KeyboardShortcuts.Recorder("翻译剪贴板", name: .translateClipboard)
            }
            Section {
                Text("Base URL 与模型即存即用；API Key 在「保存」或刷新模型时存入 Keychain，不落明文文件。"
                     + "模型列表向服务商现拉，拉不到时手填照样能用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            // 配置齐了就先把候选备好；已经有列表就不重复打扰服务商
            if models.isEmpty, !AppConfig.baseURL.isEmpty, !AppConfig.apiKey.isEmpty {
                refreshModels()
            }
        }
    }

    /// 手填永远有效，下拉只是候选：服务商不给 /models 时也不至于卡住。
    private var modelRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField("模型", text: $model, prompt: Text("如 deepseek-chat"))
                if isLoadingModels {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Menu {
                        ForEach(models, id: \.self) { name in
                            Button(name) { model = name }
                        }
                        if !models.isEmpty { Divider() }
                        Button("刷新模型列表") { refreshModels() }
                    } label: {
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }
            if let modelsError {
                Text(modelsError)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }
        }
    }

    /// 拉之前先把此刻填的 key 存进 Keychain：列表验证的配置，和翻译时真正用的，永远是同一份。
    private func refreshModels() {
        guard !isLoadingModels else { return }
        KeychainStore.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
        isLoadingModels = true
        modelsError = nil
        Task {
            do {
                models = try await ModelCatalog.fetch()
            } catch {
                models = []
                modelsError = error.localizedDescription
            }
            isLoadingModels = false
        }
    }
}
