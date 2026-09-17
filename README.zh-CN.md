<p align="center">
  <img src="Design/Banner.png" width="100%" alt="Gloss：淡墨文本线之间一条发光的金色注线，衬在一页被灯光照亮的书页上">
</p>

<h1 align="center">Gloss</h1>

<p align="center"><em>写在字里行间的那行小字。</em></p>

<p align="center">
  <a href="https://github.com/alex0811/Gloss/releases/latest">下载 macOS 版</a>
  &nbsp;·&nbsp;
  <a href="README.md">English</a>
</p>

<br>

<p align="center">γλῶσσα</p>
<p align="center"><sub>舌头 &nbsp;·&nbsp; 语言</sub></p>

**gloss** 是语言学术语「行间译注」：读外语书时写在字里行间的那行小字，一词对一词，原文照旧可读。词根是希腊语 γλῶσσα，「舌头」。英语里同拼写的另一个词义是「光泽」。图标画的就是这两层：两条淡墨文本线，其中一条下面一条金色短线，发着光。

Gloss 是一个 macOS 菜单栏翻译工具，只想做那行小字，不多做一点。无 Dock 图标，没有自己的窗口。复制、按键、读完，它就退下。

## 手势

复制。按 <kbd>⌥</kbd><kbd>⌘</kbd><kbd>T</kbd>。读。

浮层出现在鼠标附近，模型流式输出，边翻边显示，译成你选定的语言（默认简体中文）。原文是什么语种不必交代：模型自己认得，多说一句反而限制它。代码块原样留着。

浮层不抢焦点，你手头的 App 不会失去光标。点外部它不收起。再按一次热键，或点 ×，它才走。Esc 没有反应，因为按键根本到不了一个没有焦点的面板。这是设计选择，不是缺陷。

在设置里改「译成」，屏幕上这段原文立刻按新语言重翻。翻的是屏幕上这段，不是剪贴板此刻的内容。

## 图片

复制一张截图、一段聊天记录、网页上的一张图，按同一个键。

浮层先亮出原图。系统 Vision 在本地识别出文字和每一行的位置：零权限、零费用、不用选语种。识别出的行按行号整段发出去，译文回来叠在原图的原位，一行注一行，随流式输出一行行亮起来。这就是行间注本身。

原图按原尺寸显示，就是它在屏幕上原本的大小，不缩不放。浮层随图撑大，到屏幕八成封顶，之后在图区里滚动。译文只向右生长，不会压到下一行。图上放不下的长句在下方内容区一字不少，可读可复制。只想看译文，就在设置里关掉「图片翻译显示原图」。

## 不做的事

- **零权限。** 不要辅助功能，不要屏幕录制，不要完全磁盘访问。
- **只有一个 Provider。** 任何 OpenAI 兼容服务：DeepSeek、OpenAI、Ollama、中转站。换服务商就是换一个 URL。
- **密钥不落盘。** API Key 只进 Keychain，不进明文文件。
- **不吞错误。** 网络或 API 出错，浮层如实呈现。注错了比不注更糟，把原文盖住的注更糟。
- **v1 有意不做。** 划词翻译（需辅助功能权限）、历史、润色、总结。

这几条背后的五条气质准则见 [CLAUDE.md](CLAUDE.md)。

<br>

<p align="center"><img src="Design/Rule.svg" width="160" alt=""></p>

<br>

## 安装

从 [最新 Release](https://github.com/alex0811/Gloss/releases/latest) 下载 `Gloss-x.y.z.zip`，解压后把 Gloss.app 拖进「应用程序」。需要 macOS 14+，Apple 芯片与 Intel 通用。

Gloss 没有经过 Apple 公证（公证需要付费开发者账号），第一次打开会被系统拦下：

- **macOS 15 及以后**：先双击打开一次、关掉提示，再去「系统设置 → 隐私与安全性」，拉到下方，点 Gloss 旁边的「仍要打开」
- **macOS 14**：右键 Gloss.app →「打开」→「打开」
- **或者在终端里**：`xattr -dr com.apple.quarantine /Applications/Gloss.app`

应用是 ad-hoc 签名，装了新版本后系统可能询问是否允许 Gloss 访问 Keychain 里的 API Key，点「始终允许」即可。

## 配置

菜单栏图标 →「设置…」：

- **Base URL / 模型**：任何 OpenAI 兼容服务，即存即用。可以并排存几个服务商，在菜单栏里切换
- **API Key**：点「保存」存入 Keychain
- **语言**：只设「译成什么」，默认简体中文
- **翻译偏好**：可选的一段话，每次翻译都带上，如「我读的多是编程相关的英文，API、commit、PR、issue 保留英文」。单拎一小段原文，模型看不出你平时读什么，所以在这里说一次。「预设」菜单提供起手稿（编程 / 技术、学术论文、商务沟通、日常口语），选中后填进输入框，可以接着改，prompt 只认框里的字。偏好排在内置规则之后，不会破坏图片翻译的行号格式
- **快捷键**：可重新录制，默认 ⌥⌘T
- **图片翻译显示原图**：开 = 原图按原尺寸铺开、译文按原位叠上；关 = 只看译文

## 构建

```bash
swift run                # 开发运行
Scripts/bundle.sh        # 打包 dist/Gloss.app（通用二进制、ad-hoc 签名、图标由 Design/AppIcon.svg 现生成）
open dist/Gloss.app      # 日常使用
```

需要 macOS 14+ 与 Xcode 16+（打包走 `xcodebuild`，只装命令行工具不够）。也可用 Xcode 直接打开 `Package.swift` 调试。推一个 `v*` tag，GitHub Actions 会用同一条脚本打包并发布 Release。

## 许可证

[MIT](LICENSE) © ZhangFan
