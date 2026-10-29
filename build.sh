#!/bin/zsh
# Builds a universal (Apple silicon + Intel) "Codex and Claude Usage Widget.app" into ./build
set -euo pipefail
cd "$(dirname "$0")"
APP="build/Codex and Claude Usage Widget.app"
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
for arch in arm64 x86_64; do
  swiftc -O -parse-as-library -target ${arch}-apple-macos14.0 \
    Sources/main.swift -framework AppKit -o build/AIUsageMeter-$arch
done
lipo -create build/AIUsageMeter-arm64 build/AIUsageMeter-x86_64 -output "$APP/Contents/MacOS/AIUsageMeter"
rm build/AIUsageMeter-*
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --deep --sign "${SIGN_IDENTITY:--}" "$APP"
echo "Built $APP"
(cd build && ditto -c -k --keepParent "Codex and Claude Usage Widget.app" Codex-Claude-Usage-Widget-macOS.zip)
echo "Zipped build/Codex-Claude-Usage-Widget-macOS.zip"
