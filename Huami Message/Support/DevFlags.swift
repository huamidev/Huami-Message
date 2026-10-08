import Foundation

/// 开发期的调试开关，**全部集中在这一个文件里**。
///
/// 用法是在启动 App 时带上参数，例如：
///
///     xcrun simctl launch booted com.huamidev.HuamiMessage -startTab profile
///     xcrun simctl launch booted com.huamidev.HuamiMessage -openChat 1 -openAssistant 1
///     xcrun simctl launch booted com.huamidev.HuamiMessage -offline 1
///
/// 原理：`-名字 值` 形式的启动参数会被系统自动读进 UserDefaults，
/// 所以不用自己解析命令行，一行就读到了。
///
/// 两点说明：
/// 1. 这些开关在正常启动时**全部是关闭的**，不会影响你自己用、也不影响朋友用。
/// 2. 集中放一个文件，是为了将来不需要它们时，删掉一个文件就干净了 ——
///    这就是「把临时东西关进一个笼子里」的做法。
enum DevFlags {

    /// 启动时直接显示哪个 Tab：messages / profile
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

    /// 进入会话后自动打开小助手（方便看助手的流式分析 + 建议）
    static var openAssistant: Bool {
        UserDefaults.standard.bool(forKey: "openAssistant")
    }

    /// 打开小助手后**自动**开始分析（省掉手动点"帮我看看"这一步）。
    /// 纯粹为了能截图/测到流式分析和建议卡片。
    static var assistantGo: Bool {
        UserDefaults.standard.bool(forKey: "assistantGo")
    }

    /// 给第一个好友灌多少条填充消息。
    /// 用来测**长列表的滚动和性能** —— 5 条消息的列表是测不出问题的。
    static var seedMany: Int {
        UserDefaults.standard.integer(forKey: "seedMany")
    }

    /// 自检场景：滚到最顶部，然后再发一条消息。
    ///
    /// 用来验证「新消息不会把正在往上翻的用户拽到底部」这个修复 ——
    /// 正确表现是：**画面停在原地**，右下角出现一个带数字的「回到最新」。
    static var verifyScrollFix: Bool {
        UserDefaults.standard.bool(forKey: "verifyScrollFix")
    }

    /// **完全离线**：跳过一切网络请求，只用本地数据库。
    ///
    /// 这个开关不是玩具，它是用来**证明**「打开 App 瞬间就能操作」的：
    /// 打开它还能正常看到全部历史消息，就说明界面真的不依赖网络。
    /// 接上真服务器之后，这个开关会变成排查问题的一把好手 ——
    /// 能立刻分辨「是网络的问题」还是「是本地的问题」。
    static var offline: Bool {
        UserDefaults.standard.bool(forKey: "offline")
    }

    /// 进入会话后自动发一条消息（方便验证"发送 → 存库 → 重启还在"这条链路）
    static var autoSend: Bool {
        UserDefaults.standard.bool(forKey: "autoSend")
    }

    /// 让发送**必定失败**，用来验证「发送失败 + 重试」的界面。
    /// 真网络里这种失败一定会发生，所以它必须有办法被主动测到。
    static var failSend: Bool {
        UserDefaults.standard.bool(forKey: "failSend")
    }

    /// 进入会话后自动把这个好友拉黑（用来验证拉黑状态和提示条）
    static var blockChat: Bool {
        UserDefaults.standard.bool(forKey: "blockChat")
    }

    /// 进入会话后自动打开举报面板（用来验证举报流程）
    static var openReport: Bool {
        UserDefaults.standard.bool(forKey: "openReport")
    }

    /// 进入会话后自动删除这个会话（用来验证删除不会留下孤儿数据）
    static var devDeleteChat: Bool {
        UserDefaults.standard.bool(forKey: "devDeleteChat")
    }
}
