<p align="center">
  <img src="Design/AppIcon.svg" width="128" alt="Gloss icon: a glowing golden gloss line between two faint lines of ink">
</p>

<h1 align="center">Gloss</h1>

<p align="center">A macOS menu bar translator: copy text or an image → press the hotkey (⌥⌘T) → a floating panel streams the translation.</p>

<p align="center"><a href="https://github.com/alex0811/Gloss/releases/latest">Download</a></p>

<p align="center">English · <a href="README.zh-CN.md">简体中文</a></p>

A **gloss** is the line of small type written between the lines of a foreign text — an *interlinear gloss*, from Greek γλῶσσα, "tongue, language." The other word spelled the same way means shine, polish: translation and polish in one word. The icon draws exactly that — a glowing golden gloss line between two faint lines of ink. The five house rules are in [CLAUDE.md](CLAUDE.md) (Chinese).

## Install

Download `Gloss-x.y.z.zip` from the [latest release](https://github.com/alex0811/Gloss/releases/latest), unzip it, and drag Gloss.app into Applications. Requires macOS 14+; the build is universal (Apple silicon and Intel).

Gloss is not notarized by Apple (that needs a paid developer account), so macOS blocks it the first time:

- **macOS 15 and later:** open Gloss once and dismiss the warning, then go to System Settings → Privacy & Security, scroll down, and click 「Open Anyway」 next to Gloss.
- **macOS 14:** right-click Gloss.app → Open → Open.
- **Or in Terminal:** `xattr -dr com.apple.quarantine /Applications/Gloss.app`

The app is ad-hoc signed, so after installing a new version macOS may ask whether Gloss can access its API key in the Keychain. Click 「Always Allow」.

## Build and run

```bash
swift run                # develop
Scripts/bundle.sh        # package dist/Gloss.app (universal, ad-hoc signed, icon from Design/AppIcon.svg)
open dist/Gloss.app      # everyday use
```

Requires macOS 14+ and Xcode 16+ (packaging uses `xcodebuild`, so the Command Line Tools alone are not enough). You can also open `Package.swift` in Xcode directly.

## Configure

Menu bar icon → 「设置…」 (Settings — the app's own UI is Chinese for now):

- **Base URL / model** — any OpenAI-compatible service (DeepSeek, OpenAI, Ollama, a relay…), saved as you type. Keep several providers side by side and switch between them from the menu bar.
- **API key** — press 「保存」 (Save) and it goes into the Keychain, never into a plaintext file.
- **Language** — you set only *what to translate into*; Simplified Chinese by default. The source language is never declared: the model recognizes it on its own, and naming it would only constrain it.
- **Translation notes** — optional free text sent with every request, such as "I mostly read programming English; keep API, commit, PR and issue in English." A short snippet does not tell the model what you usually read, so you say it once here. The 「预设」 menu fills the box with a starting draft (programming, academic papers, business, casual) that you can then edit; the box is the only thing the prompt reads. The notes rank below the built-in rules, so they cannot break the line-number format used for images.
- **Hotkey** — re-recordable, ⌥⌘T by default.
- **「图片翻译显示原图」** (show the source image) — on: the picture is laid out at natural size with the translation overlaid line by line, and the panel grows to fit; off: translation only.

Zero system permissions — no Accessibility, no Screen Recording, no Full Disk Access.

## Use

Copy text or an image, press the hotkey. The panel opens near the pointer and fills in as it streams, translating into the language set in Settings (Simplified Chinese by default); the source language is left to the model, and code blocks are left alone.

When the clipboard holds an image — a screenshot, a chat log, a picture from a web page — the panel shows the picture first while Apple's Vision framework reads the text and the position of every line, locally: no permissions, no cost, and Vision decides the language itself. Those lines then go out as one numbered batch and come back onto the picture in place, each translation over its own line, lighting up row by row as the stream arrives. That is the interlinear gloss, literally. The image is shown at natural size — exactly as large as it was on screen, neither scaled up nor down — and the panel grows with it; at 80% of the screen's visible area it stops growing and the image area scrolls instead. A translated line only grows rightward, so it never covers the line below; anything too long for the picture is repeated in full in the content area underneath, readable and selectable. Turn off 「图片翻译显示原图」 if you only want the text.

**Changing the language:** pick another target in Settings and the text on the panel is re-translated at once, no confirmation needed. It re-translates what is on screen, not whatever the clipboard holds by now; for an image, recognition doesn't run again — the lines are still there, they just go out once more in another language.

**Closing the panel:** press the hotkey again, or click × in the top-right corner. The panel stays put — clicking outside doesn't dismiss it, so you can keep the translation open while you work. It is a non-activating panel and never takes focus from the app in front, which is why **Esc doesn't close it**: the key never reaches it. A choice, not a defect.

## v1 boundaries (deliberately left out)

- Translating a selection in place (needs the Accessibility permission — v2 at the earliest)
- History, rewriting, summarizing

## License

[MIT](LICENSE) © ZhangFan
