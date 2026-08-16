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

    var body: some View {
        Form {
            Section("服务（OpenAI 兼容协议）") {
                TextField("Base URL", text: $baseURL, prompt: Text("如 https://api.deepseek.com"))
                TextField("模型", text: $model, prompt: Text("如 deepseek-chat"))
                HStack {
                    SecureField("API Key", text: $apiKey, prompt: Text("sk-…"))
                    Button(keyJustSaved ? "已存入 Keychain" : "保存") {
                        KeychainStore.save(apiKey)
                        keyJustSaved = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            keyJustSaved = false
                        }
                    }
                    .disabled(keyJustSaved)
                }
            }
            Section("快捷键") {
                KeyboardShortcuts.Recorder("翻译剪贴板", name: .translateClipboard)
            }
            Section {
                Text("Base URL 与模型即存即用；API Key 点「保存」后存入 Keychain，不落明文文件。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}
