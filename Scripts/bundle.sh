#!/bin/bash
# 打包 Gloss.app：xcodebuild 通用二进制 + 手工组装 bundle + 签名（默认 adhoc）。
# 用法：Scripts/bundle.sh [版本号]   版本号不带 v；省略时取最近的 v* tag，没有 tag 记作 0.0.0。
# 环境变量 GLOSS_SIGN_IDENTITY：设了就用这张证书签（只给本机日常打包用），不设即 adhoc（CI 发版走这条）。
# 本地日常用和 GitHub Release 发出去的是同一条路径，本机试过的就是别人下到的。
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.0.0}"
BUILD_NUMBER="$(git rev-list --count HEAD)"

# 不用 swift build：SwiftPM 命令行生成的 Bundle.module 只找 .app 根目录和本机 .build 绝对路径，
# 根目录放不进签名、别人机器上没有 .build，打开设置（快捷键录制器取本地化文案）就 fatalError。
# xcodebuild 生成的会找 Contents/Resources。架构显式写明，出 arm64 + x86_64 通用二进制。
# 它会警告「多个匹配目标」（另一个是 Mac Catalyst），取第一个即 macOS，无害。
DERIVED=".build/xcode"
xcodebuild -scheme Gloss -configuration Release -destination 'generic/platform=macOS' \
    ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
    -derivedDataPath "$DERIVED" -quiet build
PRODUCTS="$DERIVED/Build/Products/Release"

APP="dist/Gloss.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$PRODUCTS/Gloss" "$APP/Contents/MacOS/Gloss"
# 依赖包的资源 bundle 一个不落：以后多一个带资源的依赖也不用回来改这里
for bundle in "$PRODUCTS"/*.bundle; do
    [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done

swift Scripts/render-icon.swift Design/AppIcon.svg "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key><string>com.zfanchor.gloss</string>
	<key>CFBundleName</key><string>Gloss</string>
	<key>CFBundleDisplayName</key><string>Gloss</string>
	<key>CFBundleExecutable</key><string>Gloss</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>${VERSION}</string>
	<key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>LSUIElement</key><true/>
	<key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# adhoc 签名的 designated requirement 是二进制哈希，每次打包都变，Keychain 认不出是同一个 App，
# 于是每次都弹窗要密码。证书签名的 requirement 是「bundle ID + 证书」，重打包不变，点过一次「始终允许」就不再问。
SIGN_IDENTITY="${GLOSS_SIGN_IDENTITY:--}"
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
echo "✓ 已生成 ${APP}（版本 ${VERSION}，构建号 ${BUILD_NUMBER}，$(lipo -archs "$APP/Contents/MacOS/Gloss")，签名 ${GLOSS_SIGN_IDENTITY:-adhoc}）"
