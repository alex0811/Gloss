import AppKit
import SwiftUI
import KeyboardShortcuts

@main
struct GlossApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            Button(translateTitle) { AppState.shared.translateClipboard() }
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
        // 无 Dock 图标、无主窗口：直接 swift run 时也保持菜单栏形态
        NSApp.setActivationPolicy(.accessory)
        _ = AppState.shared
    }
}
