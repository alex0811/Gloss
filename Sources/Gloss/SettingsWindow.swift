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
    @ObservedObject private var store = ProviderStore.shared
    @State private var apiKey = ""
    @State private var keyJustSaved = false
    @State private var models: [String] = []
    @State private var isLoadingModels = false
    @State private var modelsError: String?
    @State private var confirmingDelete = false
    /// 每次刷新 / 切换档案递增；过期请求的结果直接作废，防止串档案。
    @State private var fetchGeneration = 0

    var body: some View {
        Form {
            Section("服务商") {
                HStack(spacing: 8) {
                    Picker("当前", selection: $store.activeID) {
                        ForEach(store.providers) { provider in
                            Text(provider.displayName).tag(Optional(provider.id))
                        }
                    }
                    Button {
                        store.addProvider()
                    } label: {
                        Image(systemName: "plus")
                    }
                    Button {
                        confirmingDelete = true
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(store.providers.count <= 1)
                }
                .confirmationDialog(
                    "删除「\(store.active?.displayName ?? "")」？",
                    isPresented: $confirmingDelete
                ) {
                    Button("删除", role: .destructive) { store.removeActive() }
                } message: {
                    Text("它的 API Key 也会一并从 Keychain 移除。")
                }
            }
            if let index = store.activeIndex {
                let provider = $store.providers[index]
                Section("服务（OpenAI 兼容协议）") {
                    TextField("名称", text: provider.name, prompt: Text("如 DeepSeek"))
                    TextField("Base URL", text: provider.baseURL, prompt: Text("如 https://api.deepseek.com"))
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
                    modelRow(model: provider.model)
                }
            }
            Section("快捷键") {
                KeyboardShortcuts.Recorder("翻译剪贴板", name: .translateClipboard)
            }
            Section {
                Text("名称、Base URL 与模型即存即用；API Key 在「保存」或刷新模型时存入 Keychain，"
                     + "按服务商分开存，不落明文文件。模型列表向服务商现拉，拉不到时手填照样能用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .task { syncFromActive() }
        .onChange(of: store.activeID) { syncFromActive() }
    }

    /// 手填永远有效，下拉只是候选：服务商不给 /models 时也不至于卡住。
    private func modelRow(model: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField("模型", text: model, prompt: Text("如 deepseek-chat"))
                if isLoadingModels {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Menu {
                        ForEach(models, id: \.self) { name in
                            Button(name) { model.wrappedValue = name }
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

    /// 档案切换（含打开设置）时：key 从新档案的 Keychain 重新载入，模型列表清空重拉。
    /// 顺序要紧：先载 key 再刷新，刷新才不会把旧档案的 key 写进新档案。
    private func syncFromActive() {
        fetchGeneration += 1
        isLoadingModels = false
        apiKey = AppConfig.apiKey
        models = []
        modelsError = nil
        if !AppConfig.baseURL.isEmpty, !AppConfig.apiKey.isEmpty {
            refreshModels()
        }
    }

    /// 拉之前先把此刻填的 key 存进当前档案的 Keychain：
    /// 列表验证的配置，和翻译时真正用的，永远是同一份。
    private func refreshModels() {
        guard let provider = store.active else { return }
        KeychainStore.save(
            apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            account: provider.keychainAccount
        )
        fetchGeneration += 1
        let generation = fetchGeneration
        isLoadingModels = true
        modelsError = nil
        Task {
            var fetched: [String] = []
            var failure: String?
            do {
                fetched = try await ModelCatalog.fetch()
            } catch {
                failure = error.localizedDescription
            }
            guard generation == fetchGeneration else { return }
            models = fetched
            modelsError = failure
            isLoadingModels = false
        }
    }
}
