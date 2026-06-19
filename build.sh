#!/bin/bash
set -e

# ── 安卓文件小助理 构建脚本 ──────────────────────────
# 用途: 编译 Swift 源码 → 打包 .app → 内嵌 adb
# 输出: build/安卓文件小助理.app

APP_NAME="安卓文件小助理"
BINARY_NAME="AndroidFileManager"
BUILD_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$BUILD_DIR/build"
APP_BUNDLE="$OUT_DIR/$APP_NAME.app"

echo "🔨 编译 $BINARY_NAME..."
cd "$BUILD_DIR"
swift build -c release

echo ""
echo "📦 创建 App Bundle..."

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 1. 复制可执行文件
cp "$BUILD_DIR/.build/arm64-apple-macosx/release/$BINARY_NAME" \
   "$APP_BUNDLE/Contents/MacOS/$BINARY_NAME"

# 2. 生成 Info.plist（修正 Bundle ID）
cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleDisplayName</key>
    <string>安卓文件小助理</string>
    <key>CFBundleExecutable</key>
    <string>AndroidFileManager</string>
    <key>CFBundleIdentifier</key>
    <string>com.altair.android-file-assistant</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>安卓文件小助理</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>4.0.0</string>
    <key>CFBundleVersion</key>
    <string>4.0.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# 3. 内嵌 adb（从 Xcode 构建产物或手动放置的 adb）
ADB_SOURCE=""
[ -f "$BUILD_DIR/adb" ] && ADB_SOURCE="$BUILD_DIR/adb"
[ -f "$BUILD_DIR/Resources/adb" ] && ADB_SOURCE="$BUILD_DIR/Resources/adb"
# 回退：从现有 .app 中提取
[ -z "$ADB_SOURCE" ] && [ -f "/Applications/$APP_NAME.app/Contents/Resources/adb" ] && \
    ADB_SOURCE="/Applications/$APP_NAME.app/Contents/Resources/adb"
# 再回退：从桌面旧版提取
[ -z "$ADB_SOURCE" ] && [ -f "$HOME/Desktop/$APP_NAME/$APP_NAME.app/Contents/Resources/adb" ] && \
    ADB_SOURCE="$HOME/Desktop/$APP_NAME/$APP_NAME.app/Contents/Resources/adb"

if [ -n "$ADB_SOURCE" ]; then
    cp "$ADB_SOURCE" "$APP_BUNDLE/Contents/Resources/adb"
    chmod +x "$APP_BUNDLE/Contents/Resources/adb"
    echo "✅ adb 已内嵌（来自 $ADB_SOURCE）"
else
    echo "⚠️  未找到 adb 二进制，请手动放置 adb 到 $APP_BUNDLE/Contents/Resources/adb"
fi

# 3.5 内嵌 aapt（用于解析 APK 信息）
AAPT_SOURCE=""
[ -f "$BUILD_DIR/aapt" ] && AAPT_SOURCE="$BUILD_DIR/aapt"
[ -f "$BUILD_DIR/Resources/aapt" ] && AAPT_SOURCE="$BUILD_DIR/Resources/aapt"
# 回退：从现有 .app 中提取
[ -z "$AAPT_SOURCE" ] && ADB_SOURCE_DIR=$(dirname "$ADB_SOURCE") && [ -f "$ADB_SOURCE_DIR/aapt" ] && \
    AAPT_SOURCE="$ADB_SOURCE_DIR/aapt"
[ -z "$AAPT_SOURCE" ] && [ -f "/Applications/$APP_NAME.app/Contents/Resources/aapt" ] && \
    AAPT_SOURCE="/Applications/$APP_NAME.app/Contents/Resources/aapt"

if [ -n "$AAPT_SOURCE" ]; then
    cp "$AAPT_SOURCE" "$APP_BUNDLE/Contents/Resources/aapt"
    chmod +x "$APP_BUNDLE/Contents/Resources/aapt"
    echo "✅ aapt 已内嵌（来自 $AAPT_SOURCE）"
else
    echo "⚠️  未找到 aapt 二进制，APK 名称/图标解析将降级"
fi

# 3.6 内嵌 scrcpy + scrcpy-server（屏幕镜像）
SCRCPY_SOURCE="$BUILD_DIR/scrcpy"
SCRCPY_SERVER_SOURCE="$BUILD_DIR/scrcpy-server"
if [ -f "$SCRCPY_SOURCE" ] && [ -f "$SCRCPY_SERVER_SOURCE" ]; then
    cp "$SCRCPY_SOURCE" "$APP_BUNDLE/Contents/Resources/scrcpy"
    cp "$SCRCPY_SERVER_SOURCE" "$APP_BUNDLE/Contents/Resources/scrcpy-server"
    chmod +x "$APP_BUNDLE/Contents/Resources/scrcpy"
    echo "✅ scrcpy 已内嵌"
else
    echo "⚠️  未找到 scrcpy/scrcpy-server，屏幕镜像功能不可用"
fi

# 4. 复制 AppIcon（如果有）
if [ -f "$BUILD_DIR/Resources/AppIcon.icns" ]; then
    cp "$BUILD_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
    echo "✅ AppIcon 已复制（来自项目 Resources）"
elif [ -f "$HOME/Desktop/安卓文件小助理/安卓文件小助理.app/Contents/Resources/AppIcon.icns" ]; then
    cp "$HOME/Desktop/安卓文件小助理/安卓文件小助理.app/Contents/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
    echo "✅ AppIcon 已复制（来自桌面旧版）"
elif [ -f "$HOME/Desktop/AppIcon.icns" ]; then
    cp "$HOME/Desktop/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
    echo "✅ AppIcon 已复制（来自桌面）"
fi

# 5. 代码签名（可选，开发环境跳过不影响运行）
if [ -n "$CODE_SIGN_IDENTITY" ]; then
    echo "🔐 代码签名..."
    codesign --force --deep --sign "$CODE_SIGN_IDENTITY" "$APP_BUNDLE"
fi

echo ""
echo "✅ 构建完成: $APP_BUNDLE"
echo "📏 大小: $(du -sh "$APP_BUNDLE" | cut -f1)"
