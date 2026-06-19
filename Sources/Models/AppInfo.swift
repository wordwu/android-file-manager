import Foundation

/// 应用信息模型
struct AppInfo: Identifiable, Hashable {
    let id = UUID()
    let packageName: String
    let apkPath: String
    let isSystem: Bool
    var resolvedName: String?
    var iconPath: String?
    
    /// 显示名称（优先 aapt 解析 > 对照表 > 包名末段）
    var displayName: String {
        if let name = resolvedName { return name }
        if let name = Self.knownNames[packageName] { return name }
        return packageName.components(separatedBy: ".").last ?? packageName
    }


    // MARK: - 常用应用名称对照表
    static let knownNames: [String: String] = [
        // 社交
        "com.tencent.mm": "微信",
        "com.tencent.mobileqq": "QQ",
        "com.tencent.wework": "企业微信",
        "com.sina.weibo": "微博",
        "com.zhihu.android": "知乎",
        "com.ss.android.ugc.aweme": "抖音",
        "com.smile.gifmaker": "快手",
        "com.ss.android.article.news": "今日头条",
        "com.xingin.xhs": "小红书",
        "com.baidu.tieba": "百度贴吧",
        // 购物
        "com.taobao.taobao": "淘宝",
        "com.tmall.wireless": "天猫",
        "com.jingdong.app.mall": "京东",
        "com.xunmeng.pinduoduo": "拼多多",
        "com.xiaomi.shop": "小米商城",
        "com.xiaomi.youpin": "小米有品",
        "me.ele": "饿了么",
        "com.sankuai.meituan": "美团",
        "com.sankuai.meituan.takeoutnew": "美团外卖",
        "ctrip.android.view": "携程",
        "com.Qunar": "去哪儿",
        "com.dianping.v1": "大众点评",
        // 支付
        "com.eg.android.AlipayGphone": "支付宝",
        // 出行
        "com.autonavi.minimap": "高德地图",
        "com.baidu.BaiduMap": "百度地图",
        "com.didiglobal.passenger": "滴滴出行",
        "com.didi.es.psngr": "滴滴出行",
        "com.ss.android.lark": "飞书",
        // 影音
        "com.tencent.qqlive": "腾讯视频",
        "com.youku.phone": "优酷",
        "com.qiyi.video": "爱奇艺",
        "tv.danmaku.bili": "哔哩哔哩",
        "com.kugou.android": "酷狗音乐",
        "com.tencent.qqmusic": "QQ音乐",
        "com.netease.cloudmusic": "网易云音乐",
        "com.xiaomi.smarthome": "米家",
        "com.coolkit": "易微联",
        "com.miui.video": "小米视频",
        "com.miui.player": "小米音乐",
        "com.mi.health": "小米健康",
        "com.miui.weather2": "天气",
        "com.miui.notes": "便签",
        "com.miui.calculator": "计算器",
        "com.miui.compass": "指南针",
        "com.miui.screenrecorder": "屏幕录制",
        "com.miui.cleanmaster": "垃圾清理",
        "com.miui.securitycenter": "安全中心",
        "com.miui.powerkeeper": "电量管理",
        "com.miui.backup": "备份",
        "com.miui.fm": "收音机",
        "com.miui.gallery": "相册",
        "com.miui.themestore": "主题壁纸",
        "com.miui.miservice": "服务与反馈",
        "com.miui.cloudservice": "小米云服务",
        "com.miui.cloudbackup": "云备份",
        "com.xiaomi.account": "小米账户",
        "com.xiaomi.payment": "米币支付",
        "com.xiaomi.gamecenter": "游戏中心",
        "com.xiaomi.market": "应用商店",
        "com.xiaomi.scanner": "扫一扫",
        "com.xiaomi.mibrain.speech": "小爱同学",
        "com.xiaomi.discover": "小米社区",
        "com.xiaomi.vipaccount": "小米会员",
        "com.android.browser": "浏览器",
        "com.android.chrome": "Chrome",
        "com.android.email": "邮件",
        "com.android.calendar": "日历",
        "com.android.deskclock": "时钟",
        "com.android.soundrecorder": "录音机",
        "com.android.fileexplorer": "文件管理",
        "com.android.contacts": "联系人",
        "com.android.dialer": "电话",
        "com.android.mms": "短信",
        "com.android.camera": "相机",
        "com.android.calculator2": "计算器",
        "com.android.settings": "设置",
        "com.android.vending": "Play 商店",
        "com.google.android.gm": "Gmail",
        "com.google.android.apps.maps": "Google 地图",
        "com.google.android.youtube": "YouTube",
        "com.google.android.apps.photos": "Google 相册",
        "com.google.android.apps.docs": "Google 文档",
        "com.google.android.apps.bard": "Google Bard",
        "com.google.android.keep": "Google Keep",
        // 工具
        "com.iflytek.inputmethod.miui": "搜狗输入法小米版",
        "com.baidu.input_mi": "百度输入法小米版",
        "com.sohu.inputmethod.sogou": "搜狗输入法",
        "com.tencent.wetype": "微信输入法",
        "dji.mimo": "DJI Mimo",
        "dji.go.v4": "DJI GO 4",
        "dji.pilot": "DJI Pilot",
        "com.niksoftware.snapseed": "Snapseed",
        "com.adobe.lrmobile": "Lightroom",
        "com.pinterest": "Pinterest",
        "com.phoenix.read": "凤凰新闻",
        "com.miHoYo.Nap": "绝区零",
        "com.miHoYo.ys.mi": "原神",
        "com.miHoYo.hkrpg": "星穹铁道",
        "com.tencent.tmgp.sgame": "王者荣耀",
        "com.tencent.tmgp.pubgmhd": "和平精英",
        "com.tencent.tmgp.cf": "穿越火线",
        "com.netease.xyqy": "梦幻西游",
        "com.netease.onmyoji": "阴阳师",
        "com.shangyoo.newworld": "天涯明月刀",
    ]
}