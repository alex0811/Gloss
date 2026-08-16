<p align="center">
  <img src="Design/AppIcon.svg" width="128" alt="Gloss 图标：淡墨文本线之间，一条发光的金色注线">
</p>

<h1 align="center">Gloss</h1>

<p align="center">macOS 菜单栏翻译工具：复制文本 → 全局热键（默认 ⌥⌘T）→ 浮层流式译文。</p>

**gloss**，语言学术语「行间译注」——外语书页字里行间那行小字翻译；英语里同拼写的另一个词义是「光泽、润色」。图标画的就是它：两条淡墨文本线之间，一条发光的金色注线。项目气质见 [CLAUDE.md](CLAUDE.md)。

## 构建与运行

```bash
swift run                # 开发运行
Scripts/bundle.sh        # 打包 dist/Gloss.app
open dist/Gloss.app      # 日常使用
```

也可用 Xcode 直接打开 `Package.swift` 调试。

## 配置

菜单栏图标 →「设置…」：

- **Base URL / 模型**：任何 OpenAI 兼容服务（DeepSeek、OpenAI、Ollama、中转站……），即存即用
- **API Key**：点「保存」存入 Keychain，不落明文文件
- **快捷键**：可重新录制，默认 ⌥⌘T

## 使用

复制一段文本，按热键。浮层出现在鼠标附近，边翻边显示；中英自动互译，代码块不翻。

关闭浮层：点浮层外任意处 / 再按一次热键 / 右上角 ×。
浮层是非激活面板，不抢当前 App 的焦点——因此 **Esc 不关闭浮层**（按键根本到不了它），这是设计选择而非缺陷。

## v1 边界（有意不做）

- 划词翻译（需辅助功能权限，v2 再说）
- 翻译历史、润色/总结
- 目标语言选择（当前固定中英自动互译）
- App 图标 .icns 生成（母版在 `Design/AppIcon.svg`）
