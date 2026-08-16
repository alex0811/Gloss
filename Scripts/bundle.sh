#!/bin/bash
# 打包 Gloss.app：release 构建 + 手工组装 bundle + adhoc 签名。
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="dist/Gloss.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Gloss "$APP/Contents/MacOS/Gloss"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key><string>com.zfanchor.gloss</string>
	<key>CFBundleName</key><string>Gloss</string>
	<key>CFBundleDisplayName</key><string>Gloss</string>
	<key>CFBundleExecutable</key><string>Gloss</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>0.1.0</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>LSUIElement</key><true/>
	<key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "✓ 已生成 ${APP}（App 图标 .icns 待生成，见 Design/AppIcon.svg）"
