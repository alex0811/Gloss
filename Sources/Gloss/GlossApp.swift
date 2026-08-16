import AppKit
import SwiftUI
import KeyboardShortcuts

@main
struct GlossApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = ProviderStore.shared

    var body: some Scene {
        MenuBarExtra {
            Button(translateTitle) { AppState.shared.translateClipboard() }
            if store.providers.count > 1 {
                Divider()
                Picker("服务商", selection: $store.activeID) {
                    ForEach(store.providers) { provider in
                        Text(provider.displayName).tag(Optional(provider.id))
                    }
                }
                .pickerStyle(.inline)
            }
            Divider()
            Button("设置…") { SettingsWindowController.shared.show() }
            Divider()
            Button("退出 Gloss") { NSApp.terminate(nil) }
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
    }

    private var translateTitle: String {
        if let shortcut = KeyboardShortcuts.getShortcut(for: .translateClipboard) {
            return "翻译剪贴板　\(shortcut)"
        }
        return "翻译剪贴板"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 旧的单份配置迁成第一个服务商档案（幂等；ProviderStore 初始化时也会兜底）
        ProviderRepo.bootstrap()
        // 无 Dock 图标、无主窗口：直接 swift run 时也保持菜单栏形态
        NSApp.setActivationPolicy(.accessory)
        _ = AppState.shared
    }
}
