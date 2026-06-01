#!/usr/bin/env bash
# 把 swift build 产物打包成正式 MiniFriend.app（带 Info.plist + 资源 + ad-hoc 签名），
# 这样麦克风/语音识别权限弹窗才正常，不再闪退。
set -euo pipefail
cd "$(dirname "$0")"

CONFIG=debug
swift build -c $CONFIG
BIN_DIR=".build/$CONFIG"

APP="MiniFriend.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# 可执行文件
cp "$BIN_DIR/MiniFriend" "$APP/Contents/MacOS/MiniFriend"

# SPM 资源 bundle（Bundle.module 会在主 bundle 的 Resources 里找到它）
if [ -d "$BIN_DIR/MiniFriend_MiniFriend.bundle" ]; then
    cp -R "$BIN_DIR/MiniFriend_MiniFriend.bundle" "$APP/Contents/Resources/"
fi

# Info.plist（权限说明 + bundle id + 无 Dock 图标）
cp Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string MiniFriend" "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 1.0" "$APP/Contents/Info.plist" 2>/dev/null || true

# ad-hoc 签名（TCC 需要稳定签名身份来记住授权）
codesign --force --deep --sign - "$APP"

echo "打包完成 -> $APP"
echo "运行：open $APP    （或双击）"
