<p align="center">
  <img src="Design/Banner.png" width="100%" alt="Gloss: the app icon, a golden gloss line between two lines of ink, over a page lit from behind">
</p>

<h1 align="center">Gloss</h1>

<p align="center"><em>The small line written between the lines.</em></p>

<p align="center">
  <a href="https://github.com/alex0811/Gloss/releases/latest">Download for macOS</a>
  &nbsp;·&nbsp;
  <a href="README.zh-CN.md">简体中文</a>
</p>

<br>

<p align="center">γλῶσσα</p>
<p align="center"><sub>tongue &nbsp;·&nbsp; language</sub></p>

A **gloss** is the line of small type a reader writes between the lines of a foreign text: word under word, so the page can still be read as it was. The word comes from Greek γλῶσσα, *tongue*. The English word spelled the same way means *shine*. The icon is both at once: two faint lines of ink, and under one of them a short golden line, lit.

Gloss is a macOS menu bar translator that tries to be that line and nothing more. No Dock icon, no window of its own. You copy, you press a key, you read, and it goes away.

## The gesture

Copy. Press <kbd>⌥</kbd><kbd>⌘</kbd><kbd>T</kbd>. Read.

A panel opens near the pointer and fills in as the model streams, into the language you chose (Simplified Chinese by default). The source language is never declared. The model recognizes it, and naming it would only constrain it. Code blocks are left as they are.

The panel takes no focus, so the app in front of you never loses its place. Click outside and it stays. Press the hotkey again, or ×, and it goes. Esc does nothing, because Esc never reaches a panel that has no focus. That is a choice, not a defect.

Change the target language in Settings and the text on screen is translated again at once. The text on screen, not whatever the clipboard holds by now.

## The picture

Copy a screenshot, a chat log, a picture from a web page, and press the same key.

The panel shows the picture first. Apple's Vision framework reads the text on it, locally, line by line, with the position of every line: no permission, no cost, no language to choose. The lines go out as one numbered batch and come back onto the picture in place, each translation over its own line, lighting up row by row as the stream arrives. That is an interlinear gloss, literally.

The picture is shown at natural size, exactly as large as it was on screen. The panel grows with it, up to 80% of the screen, and scrolls after that. A translated line only grows rightward and never covers the line below. Anything too long for the picture is repeated in full underneath, selectable. Turn off 「图片翻译显示原图」 in Settings if you want the text alone.

## What it leaves out

- **No permissions.** No Accessibility, no Screen Recording, no Full Disk Access.
- **One provider.** Any OpenAI-compatible endpoint: DeepSeek, OpenAI, Ollama, a relay. Changing service is changing a URL.
- **No secrets on disk.** The API key lives in the Keychain, never in a plaintext file.
- **No hidden errors.** When the network or the API fails, the panel says so. A gloss that hides the text is worse than none.
- **Not in v1, on purpose.** Translating a selection in place (needs Accessibility), history, rewriting, summarizing.

The five house rules behind these are in [CLAUDE.md](CLAUDE.md) (Chinese).

<br>

<p align="center"><img src="Design/Rule.svg" width="160" alt=""></p>

<br>

## Install

Download `Gloss-x.y.z.zip` from the [latest release](https://github.com/alex0811/Gloss/releases/latest), unzip it, and drag Gloss.app into Applications. Requires macOS 14+; the build is universal (Apple silicon and Intel).

Gloss is not notarized by Apple (that needs a paid developer account), so macOS blocks it the first time:

- **macOS 15 and later:** open Gloss once and dismiss the warning, then go to System Settings → Privacy & Security, scroll down, and click 「Open Anyway」 next to Gloss.
- **macOS 14:** right-click Gloss.app → Open → Open.
- **Or in Terminal:** `xattr -dr com.apple.quarantine /Applications/Gloss.app`

The app is ad-hoc signed, so after installing a new version macOS may ask whether Gloss can access its API key in the Keychain. Click 「Always Allow」.

## Configure

Menu bar icon → 「设置…」 (Settings; the app's own UI is Chinese for now):

- **Base URL / model.** Any OpenAI-compatible service, saved as you type. Keep several providers side by side and switch between them from the menu bar.
- **API key.** Press 「保存」 (Save) and it goes into the Keychain.
- **Language.** Only *what to translate into*. Simplified Chinese by default.
- **Translation notes.** An optional paragraph sent with every request, such as "I mostly read programming English; keep API, commit, PR and issue in English." A short snippet cannot tell the model what you usually read, so you say it once here. The 「预设」 menu fills the box with a starting draft (programming, academic papers, business, casual) that you then edit; the box is the only thing the prompt reads. The notes rank below the built-in rules, so they cannot break the line-number format used for images.
- **Hotkey.** Re-recordable, ⌥⌘T by default.
- **「图片翻译显示原图」** (show the source image). On: the picture at natural size with the translation laid over it line by line. Off: translation only.

## Build

```bash
swift run                # develop
Scripts/bundle.sh        # package dist/Gloss.app (universal, ad-hoc signed, icon rendered from Design/AppIcon.svg)
open dist/Gloss.app      # everyday use
```

Requires macOS 14+ and Xcode 16+ (packaging uses `xcodebuild`, so the Command Line Tools alone are not enough). You can also open `Package.swift` in Xcode directly. Pushing a `v*` tag builds the same package on GitHub Actions and publishes it as a release.

## License

[MIT](LICENSE) © ZhangFan
