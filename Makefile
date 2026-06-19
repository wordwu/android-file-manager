# 安卓文件小助理 - Makefile
# 一键: make release

APP_NAME = AndroidFileManager
APP_BUNDLE = 安卓文件小助理.app
APP_DIR = $(HOME)/Desktop/AndroidFileManager-v2

VERSION = $(shell git describe --tags --abbrev=0 2>/dev/null || echo "2.6.0")

.PHONY: build clean release dmg

build:
	swift build -c release

clean:
	rm -rf .build

release: build
	@echo "📦 打包 $(VERSION)..."
	@# 更新 Info.plist 版本号
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" Sources/Info.plist
	@# 复制二进制
	cp .build/arm64-apple-macosx/release/$(APP_NAME) "$(APP_DIR)/$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	@# 复制 Info.plist
	cp Sources/Info.plist "$(APP_DIR)/$(APP_BUNDLE)/Contents/Info.plist"
	@# 复制 aapt 到 Resources（Universal binary，支持 ARM64 + Intel）
	@if [ -f $(HOME)/android-sdk/build-tools/35.0.0/aapt ]; then \
		cp $(HOME)/android-sdk/build-tools/35.0.0/aapt "$(APP_DIR)/$(APP_BUNDLE)/Contents/Resources/aapt"; \
		echo "✅ aapt 已内嵌"; \
	else \
		echo "⚠️  aapt 未找到，应用图标解析依赖 SDK"; \
	fi
	@# 清隔离 + 签名
	xattr -cr "$(APP_DIR)/$(APP_BUNDLE)"
	codesign --force --sign - "$(APP_DIR)/$(APP_BUNDLE)"
	@# 重建 Launch Services
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$(APP_DIR)/$(APP_BUNDLE)" 2>/dev/null
	@echo "✅ $(APP_BUNDLE) ($(VERSION)) 打包完成"
	@echo "📱 open $(APP_DIR)/$(APP_BUNDLE)"

dmg: release
	@echo "💿 制作 DMG..."
	hdiutil create -volname "安卓文件小助理" -srcfolder "$(APP_DIR)/$(APP_BUNDLE)" -ov -format UDZO \
		"$(APP_DIR)/安卓文件小助理-$(VERSION).dmg"
	@echo "✅ DMG: $(APP_DIR)/安卓文件小助理-$(VERSION).dmg"
