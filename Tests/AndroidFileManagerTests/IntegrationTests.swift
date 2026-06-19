import XCTest
@testable import AndroidFileManager

/// 集成测试：完整工作流验证
final class IntegrationTests: XCTestCase {
    
    // MARK: - 系统/三方应用分类
    
    func testAppClassification() {
        // 模拟 pm list packages -f 输出
        let output = """
        package:/system/app/Calculator.apk=com.android.calculator
        package:/data/app/~~abc==/com.example.app-xyz==/base.apk=com.example.app
        package:/vendor/app/Camera.apk=com.android.camera
        package:/product/app/Maps.apk=com.google.android.maps
        """
        
        let apps = output
            .components(separatedBy: .newlines)
            .compactMap { line -> AppInfo? in
                guard !line.isEmpty else { return nil }
                let cleaned = line.replacingOccurrences(of: "package:", with: "")
                let parts = cleaned.components(separatedBy: "=")
                guard parts.count >= 2 else { return nil }
                let path = parts[0]
                let pkg = parts[1]
                let isSys = path.hasPrefix("/system/") || path.hasPrefix("/vendor/")
                    || path.hasPrefix("/product/") || path.hasPrefix("/system_ext/")
                    || path.hasPrefix("/odm/")
                return AppInfo(packageName: pkg, apkPath: path, isSystem: isSys)
            }
        
        XCTAssertEqual(apps.count, 4)
        XCTAssertTrue(apps[0].isSystem, "system = 系统")
        XCTAssertFalse(apps[1].isSystem, "data = 三方")
        XCTAssertTrue(apps[2].isSystem, "vendor = 系统")
        XCTAssertTrue(apps[3].isSystem, "product = 系统")
    }
    
    // MARK: - 安装错误映射
    
    func testInstallErrorMapping() async {
        struct MockErr: LocalizedError {
            let desc: String
            var errorDescription: String? { desc }
        }
        
        let restricted = await ADBService.installErrorMessage(from: MockErr(desc: "USER_RESTRICTED"))
        XCTAssertTrue(restricted.contains("USB 调试"))
        
        let failed = await ADBService.installErrorMessage(from: MockErr(desc: "INSTALL_FAILED_VERSION_DOWNGRADE"))
        XCTAssertTrue(failed.contains("安装失败"))
        
        let unknown = await ADBService.installErrorMessage(from: MockErr(desc: "Some other error"))
        XCTAssertTrue(unknown.contains("安装失败"))
    }
    
    // MARK: - Constants 验证
    
    func testImageExtensions() {
        XCTAssertTrue(C.imageExts.contains("jpg"))
        XCTAssertTrue(C.imageExts.contains("png"))
        XCTAssertFalse(C.imageExts.contains("apk"))
    }
    
    func testTimeouts() {
        XCTAssertEqual(C.adbDefault, 8)
        XCTAssertEqual(C.adbInstall, 120)
        XCTAssertEqual(C.maxRetries, 2)
    }
    
    // MARK: - Shell 转义
    
    func testShellEscape() async {
        let adb = await ADBService.shared
        let safe = await adb.shellEscape("$`\"\\")
        XCTAssertTrue(safe.contains("\\$"), "美元符应被转义为 \\$")
        XCTAssertTrue(safe.contains("\\`"), "反引号应被转义为 \\`")
        XCTAssertTrue(safe.contains("\\\""), "双引号应被转义为 \\\"")
        XCTAssertTrue(safe.contains("\\\\"), "反斜杠应被转义")
    }
    
    func testShellQuote() async {
        let adb = await ADBService.shared
        let quoted = await adb.shellQuote("it's a test")
        XCTAssertTrue(quoted.hasPrefix("'"), "应以单引号开头")
        XCTAssertTrue(quoted.hasSuffix("'"), "应以单引号结尾")
    }
    
    // MARK: - ls 四级回退解析
    
    func testParseTestDOutput() {
        let output = "d|Documents\nf|photo.jpg\nf|notes.txt\n"
        let items = parseTestDOutput(output, dirPath: "/sdcard")
        
        XCTAssertEqual(items.count, 3)
        XCTAssertTrue(items[0].isDirectory)
        XCTAssertEqual(items[0].name, "Documents")
        XCTAssertFalse(items[1].isDirectory)
        XCTAssertEqual(items[1].name, "photo.jpg")
    }
    
    // MARK: - 应用显示名优先级
    
    func testDisplayNamePriority() {
        // 有 resolvedName 优先
        var app = AppInfo(packageName: "com.test.app", apkPath: "/data/app", isSystem: false)
        XCTAssertEqual(app.displayName, "app")
        
        app.resolvedName = "我的应用"
        XCTAssertEqual(app.displayName, "我的应用")
        
        // 对照表次之
        var wechat = AppInfo(packageName: "com.tencent.mm", apkPath: "/data/app", isSystem: false)
        XCTAssertEqual(wechat.displayName, "微信")
        
        wechat.resolvedName = "微信(已更新)"
        XCTAssertEqual(wechat.displayName, "微信(已更新)")
    }
    
    // MARK: - APKInfo 解析 aapt badging 输出
    
    func testAPKInfoParsing_appName() {
        // 模拟真实 aapt dump badging 输出
        let badging = "application: label='高德地图' icon='res/drawable-mdpi-v4/v3_icon.png'"
        let info = APKInfo(fromBadging: badging, fileSize: 100)
        XCTAssertFalse(info.appName.isEmpty, "appName should not be empty")
    }
}
