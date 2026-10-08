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

    /// 直接当作"已同意服务条款"（省得每次截图都手点一遍同意页）
    static var acceptTerms: Bool {
        UserDefaults.standard.bool(forKey: "acceptTerms")
    }

    /// 清掉"已同意"的标记，让同意页重新出现（用来截图/检查这一页）
    static var resetTerms: Bool {
        UserDefaults.standard.bool(forKey: "resetTerms")
    }

    /// 直接打开某份法律文档："privacy" 或 "terms"
    static var legalDoc: String {
        UserDefaults.standard.string(forKey: "legalDoc") ?? ""
    }

    /// 启动时自动打开指定名字的好友会话（截图验证用）。
    /// 比 -openChat 更精确：那个只会开第一个会话，而新加的好友排在最后。
    static var openChatName: String {
        UserDefaults.standard.string(forKey: "openChatName") ?? ""
    }

    /// 启动时自动往第一个会话发一条消息（验证真服务器发消息链路）
    static var sendText: String {
        UserDefaults.standard.string(forKey: "sendText") ?? ""
    }

    /// 启动时模拟"用户点了邮件里的确认链接"。
    ///
    /// 为什么需要它：用 `simctl openurl` 测试时，iOS 会弹一个
    /// "Open in Huami Message?" 的系统确认框，自动化点不到。
    /// 这个开关直接调用处理函数，把**跳转之后的逻辑**单独验证掉。
    static var confirmLink: String {
        UserDefaults.standard.string(forKey: "confirmLink") ?? ""
    }

    /// 启动后自动执行一次「退出登录」。
    /// 用来验证"退出之后会不会回到登录页"——这个用截图点不了按钮。
    static var devSignOut: Bool {
        UserDefaults.standard.bool(forKey: "devSignOut")
    }

    /// 启动时自动把光标放到邮箱框 —— 用来截图确认键盘长什么样。
    /// （截图没法点输入框，不这样键盘根本不出来。）
    static var focusEmail: Bool {
        UserDefaults.standard.bool(forKey: "focusEmail")
    }

    /// 启动时把搜索框填上这个词 —— 用来截图验证搜索结果
    static var searchFor: String {
        UserDefaults.standard.string(forKey: "searchFor") ?? ""
    }

    /// 启动时自动打开「编辑资料」（截图没法点按钮）
    static var openEditProfile: Bool {
        UserDefaults.standard.bool(forKey: "openEditProfile")
    }

    /// 启动时自动把简介改成这个（验证"改资料"整条链路，截图点不了保存）
    static var saveBio: String {
        UserDefaults.standard.string(forKey: "saveBio") ?? ""
    }

    /// 启动后假装收到一条好友消息（验证"自动分析"那条链路）。
    /// 假服务器没有实时推送，收不到真消息，只能这样造。
    static var incomingText: String {
        UserDefaults.standard.string(forKey: "incomingText") ?? ""
    }

    /// 启动时自动展开输入框上面的工具栏（截图点不了「+」）
    static var openTools: Bool {
        UserDefaults.standard.bool(forKey: "openTools")
    }

    /// 启动时自动打开「API 接入」
    static var openAPI: Bool {
        UserDefaults.standard.bool(forKey: "openAPI")
    }

    /// 启动后自动发一张测试图片（验证"发图片"整条链路）
    static var sendTestImage: Bool {
        UserDefaults.standard.bool(forKey: "sendTestImage")
    }

    /// 进聊天页几秒后自动返回（用来拍返回时的过渡动画）
    static var popAfter: Int {
        UserDefaults.standard.integer(forKey: "popAfter")
    }

    /// 启动后自动传一张测试头像（验证"换头像"整条链路）
    static var testAvatar: Bool {
        UserDefaults.standard.bool(forKey: "testAvatar")
    }

    /// 往账号列表里塞两个假账号（模拟器钥匙串写不进去，否则看不到这一屏）
    static var seedAccounts: Bool {
        UserDefaults.standard.bool(forKey: "seedAccounts")
    }

    /// 假装正在录音（截图没法按住按钮，得把这一屏调出来看位置）
    static var fakeRecording: Bool {
        UserDefaults.standard.bool(forKey: "fakeRecording")
    }

    /// 启动时直接进语音模式（截图点不了麦克风按钮）
    static var voiceMode: Bool {
        UserDefaults.standard.bool(forKey: "voiceMode")
    }

    /// 启动时自动打开「加好友」
    static var openAddFriend: Bool {
        UserDefaults.standard.bool(forKey: "openAddFriend")
    }

    /// 启动时自动用这个用户名加一个好友（用来验证加好友流程）
    static var addFriendCode: String {
        UserDefaults.standard.string(forKey: "addFriendCode") ?? ""
    }

    /// 启动后立刻执行"删除账号"（用来验证真的删干净了，不用手点确认框）
    static var devWipe: Bool {
        UserDefaults.standard.bool(forKey: "devWipe")
    }

    /// 启动时自动建好并登录一个测试账号（省得每次截图都手打邮箱密码）。
    ///
    /// 注意：账号是假的（存在本机 UserDefaults 里），
    /// 等接上 Supabase 之后这个开关就没用了 —— 到时候要真账号才能登录。
    static var devSignIn: Bool {
        UserDefaults.standard.bool(forKey: "devSignIn")
    }

    /// 开发用测试账号
    static let devEmail = "test@huami.app"
    static let devPassword = "huami1234"

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
