import Foundation

/// 全局常量
enum C {
    // MARK: - 超时
    static let adbDefault: TimeInterval = 8
    static let adbInstall: TimeInterval = 120
    static let adbLong: TimeInterval = 30
    static let adbShort: TimeInterval = 5
    static let adbHeartbeat: TimeInterval = 6
    
    // MARK: - 路径
    static let systemDirPrefixes = ["/system/", "/vendor/", "/product/", "/system_ext/", "/odm/"]
    static let tmpThumbPrefix = "/tmp/androidfm_thumb_"
    static let tmpPreviewPrefix = "/tmp/androidfm_preview_"
    static let tmpApkPrefix = "/tmp/androidfm_apk_"
    
    // MARK: - 图片扩展名
    static let imageExts: Set<String> = ["jpg", "jpeg", "png", "gif", "heic", "webp", "bmp"]
    static let adbPort = 5555 // 默认 ADB TCP 端口
    // ---------- 通知名称 ----------
    // MARK: - 重试
    static let maxRetries = 2
    static let retryDelaySec: TimeInterval = 1

    // MARK: - UI 常量
    static let statusMessageTTL: TimeInterval = 2.5
    static let quickLookMaxWaitAttempts = 20
    static let quickLookPollIntervalMs: UInt64 = 500
    static let adbPushPullTimeout: Double = 300
    static let copyAlertDuration: TimeInterval = 1.5
    static let mtpHintDelay: TimeInterval = 10

    // MARK: - 缩略图
    static let thumbnailSize = NSSize(width: 120, height: 120)
    static let thumbnailCacheCountLimit = 200
    static let thumbnailCacheTotalCostLimit = 20 * 1024 * 1024

    // MARK: - 设备轮询 (ticks × 2s interval)
    static let pollingIntervalSec: TimeInterval = 2
    static let heartbeatIntervalTicks = 5   // 每 10s 发送心跳
    static let networkCheckIntervalTicks = 15 // 每 30s 检查网络
    static let tcpipRestartDelaySec: TimeInterval = 3

    // MARK: - 受限路径
    static let restrictedPathPatterns: [String] = [
        "/android/data", "/android/obb", "/android/sandbox"
    ]

    // MARK: - 设备型号名称库
    static let deviceModelNames: [String: String] = [
        // 小米 / Redmi
        "24129PN74C": "小米 15",
        "2410DPN6CC": "小米 15 Pro",
        "24117RK2CC": "Redmi K80",
        "24122RKC7C": "Redmi K80 Pro",
        "2311DRK48C": "小米 14 Pro",
        "23127PN0CC": "小米 14",
        "2304FPN6DC": "小米 13 Ultra",
        "2211133C": "小米 13",
        "2210132C": "小米 13 Pro",
        "2201123C": "小米 12 Pro",
        "2201122C": "小米 12",
        "21091116C": "小米 Civi",
        "2203121C": "小米 12S Ultra",
        "2306EPN60C": "小米 13T Pro",
        "23078PND5G": "小米 13T",
        "2107119DC": "Redmi Note 10 Pro",
        "M2012K11AC": "Redmi K40",
        "M2011K2C": "Redmi K30S",
        "M2007J22C": "Redmi 10X 5G",
        "M2006C3LC": "Redmi 9A",
        // 华为
        "ALN-AL80": "华为 Mate 60 Pro",
        "ALN-AL00": "华为 Mate 60",
        "MNA-AL00": "华为 Mate X5",
        "ADA-AL00": "华为 P60 Pro",
        "LIO-AL00": "华为 Mate 30 Pro",
        "NOH-AL00": "华为 P50 Pro",
        "ALP-AL00": "华为 Mate 10",
        // OPPO / OnePlus
        "PHY110": "OPPO Find X7 Ultra",
        "PHT110": "OPPO Find X7",
        "PHW110": "OPPO Find X6 Pro",
        "PGFM10": "OPPO Find N3",
        "CPH2581": "OPPO Find X5 Pro",
        "PHB110": "OPPO Reno 10 Pro+",
        "PJA110": "OPPO Reno 9 Pro+",
        "PKH110": "OPPO Find N5",
        "PKD130": "OnePlus 12",
        "PHK110": "OnePlus Ace 3",
        "LE2100": "OnePlus 9 Pro",
        // vivo / iQOO
        "V2324A": "vivo X100 Pro",
        "V2309A": "vivo X100",
        "V2327A": "vivo X Fold3 Pro",
        "V2241A": "vivo X90 Pro",
        "V2217A": "vivo X80",
        "V2301A": "iQOO 12",
        "V2171A": "iQOO 9 Pro",
        // 荣耀
        "MAA-AN00": "荣耀 Magic 6 Pro",
        "BVL-AN00": "荣耀 Magic 5 Pro",
        "LGE-AN00": "荣耀 100 Pro",
        "MAG-AN00": "荣耀 Magic V2",
        // 三星 (国行版)
        "SM-S9280": "三星 Galaxy S24 Ultra",
        "SM-S9210": "三星 Galaxy S24",
        "SM-F9560": "三星 Galaxy Z Fold 6",
        "SM-F7410": "三星 Galaxy Z Flip 6",
        // 其他
        "sdk_gphone64_arm64": "Android 模拟器",
    ]

    // MARK: - UI 尺寸
    static let transferPanelHeight: CGFloat = 120
}
