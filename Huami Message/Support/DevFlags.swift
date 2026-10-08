import Foundation

/// 开发期的调试开关，**全部集中在这一个文件里**。
///
/// 用法是在启动 App 时带上参数，例如：
///
///     xcrun simctl launch booted com.huamidev.HuamiMessage -startTab advisor
///     xcrun simctl launch booted com.huamidev.HuamiMessage -openChat 1 -openPolish 1
///
/// 原理：`-名字 值` 形式的启动参数会被系统自动读进 UserDefaults，
/// 所以不用自己解析命令行，一行就读到了。
///
/// 两点说明：
/// 1. 这些开关在正常启动时**全部是关闭的**，不会影响你自己用、也不影响朋友用。
/// 2. 集中放一个文件，是为了将来不需要它们时，删掉一个文件就干净了 ——
///    这就是「把临时东西关进一个笼子里」的做法。
enum DevFlags {

    /// 启动时直接显示哪个 Tab：messages / advisor / profile
    static var startTab: String {
        UserDefaults.standard.string(forKey: "startTab") ?? "messages"
    }

    /// 启动时自动进入第一个会话（方便看聊天页）
    static var openChat: Bool {
        UserDefaults.standard.bool(forKey: "openChat")
    }

    /// 进入会话后自动打开 AI 润色面板（方便看润色交互）
    static var openPolish: Bool {
        UserDefaults.standard.bool(forKey: "openPolish")
    }
}
