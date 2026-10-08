import Foundation
import CryptoKit

// ============================================================================
// 账号
// ============================================================================

/// 一个已登录的账号。
///
/// 和 `Friend` 一样是个纯数据的 struct —— 界面拿它显示，
/// 但它不知道底下是 Supabase 还是别的什么。
struct Account: Identifiable, Hashable, Codable {

    /// 账号 id。接上 Supabase 之后就是 `auth.users.id`。
    let id: UUID

    var email: String

    /// 显示名。第一版直接用邮箱 @ 前面那段，以后让用户自己改。
    var displayName: String

    /// 头像底色（沿用好友头像那套：存数字，不存颜色）
    var avatarSeed: Int

    /// 邀请码。加好友靠它，不走通讯录。
    var inviteCode: String

    /// 邮箱 @ 前面那段，当默认昵称用
    static func name(from email: String) -> String {
        let head = email.split(separator: "@").first.map(String.init) ?? email
        return head.isEmpty ? "我" : head
    }
}

// ============================================================================
// 登录服务
// ============================================================================

/// 登录的「插座标准」。
///
/// 和 `ChatService`／`AIService` 是同一个思路：界面只跟这个协议说话。
/// 现在背后是假的（数据存在本机），接上 Supabase 之后换成真的 ——
/// **界面代码一行都不用改**。
///
/// 方法全是 async，因为登录**必须**经过网络。
/// 这跟本地数据库刻意保持同步是两回事：读本地不能等，登录只能等。
protocol AuthService {

    /// 启动时读一次：本地存着上次登录的账号吗？
    /// 同步方法 —— 它只是读一个本地文件，不该让开屏多等一帧。
    func currentAccount() -> Account?

    /// 注册
    func signUp(email: String, password: String) async throws -> Account

    /// 登录
    func signIn(email: String, password: String) async throws -> Account

    /// 退出登录。清掉本地存的会话，服务器那边不用通知。
    func signOut() async

    /// 发一封"重置密码"的邮件
    func sendPasswordReset(email: String) async throws

    /// **能不能在这台设备上记住登录状态。**
    ///
    /// 正常情况当然是能。但登录凭证是存在系统钥匙串里的，
    /// 而钥匙串在某些环境下会写不进去（比如没有正确签名的开发构建，
    /// 会返回 -34018 缺少权限）。
    ///
    /// 遇到那种情况，App 照样能用，只是**每次打开都要重新登录**。
    /// 与其让用户莫名其妙，不如把这件事说出来。
    var isSessionPersisted: Bool { get }
}

extension AuthService {
    /// 默认能记住。真正会失败的实现自己覆盖这一条。
    var isSessionPersisted: Bool { true }
}

// ============================================================================
// 登录会出的错
// ============================================================================

/// 登录相关的错误。
///
/// 【为什么要单独定义一个错误类型，而不是随便抛一个 Error】
///
/// 因为**这些错误是要显示给用户看的**。用户看到的必须是"这个邮箱已经注册过了"，
/// 而不是 "Error Domain=SUPABASE Code=422"。
///
/// `LocalizedError` 让每种错误自带一句人话，界面直接显示 `errorDescription` 就行，
/// 不用在界面里写一堆 if-else 去翻译错误码。
enum AuthError: LocalizedError, Equatable {

    case invalidEmail
    case weakPassword
    case passwordMismatch
    case emailAlreadyUsed
    case emailConfirmationRequired
    case wrongCredentials
    case network
    case notSignedIn
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidEmail:      "这个邮箱地址看起来不太对，检查一下？"
        case .weakPassword:      "密码至少要 8 位，建议字母加数字。"
        case .passwordMismatch:  "两次输入的密码不一样。"
        case .emailAlreadyUsed:  "这个邮箱已经注册过了，直接登录就行。"
        case .emailConfirmationRequired:
            "注册成功了。请去邮箱点一下确认链接，然后回来登录。"
        case .wrongCredentials:  "邮箱或密码不对。"
        case .network:           "网络好像不太顺，等一下再试。"
        case .notSignedIn:       "你还没有登录。"
        case .unknown(let msg):  msg
        }
    }
}

// ============================================================================
// 共用的校验规则
// ============================================================================

/// 邮箱和密码的格式检查。
///
/// 放在这里给所有实现共用 —— 这样"什么算合法密码"只有一处定义，
/// 不会出现"假实现说 8 位、真后端说 6 位"这种两边不一致的情况。
enum AuthRules {

    static let minimumPasswordLength = 8

    /// 够用的邮箱检查。
    /// 不追求完美（那需要发验证邮件才算数），只挡住明显的笔误：
    /// 没有 @、@ 前后为空、没有点。
    static func isValidEmail(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard let at = trimmed.firstIndex(of: "@"), trimmed.filter({ $0 == "@" }).count == 1 else {
            return false
        }
        let name = trimmed[trimmed.startIndex..<at]
        let domain = trimmed[trimmed.index(after: at)...]
        return !name.isEmpty && domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }

    static func isValidPassword(_ password: String) -> Bool {
        password.count >= minimumPasswordLength
    }

    /// 生成一个邀请码。
    /// 去掉容易看错的 0/O/1/I —— 这个码是要用户手打的。
    static func makeInviteCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<8).map { _ in alphabet.randomElement()! })
    }
}

// ============================================================================
// 本地加密小工具
// ============================================================================

/// 给密码加盐做摘要。
///
/// ⚠️ **说清楚：这只是假实现里避免明文存密码用的。**
/// 真正的密码校验永远在服务器上做（Supabase 用 bcrypt），
/// 客户端这边就算算得再花哨也没有安全意义 ——
/// 因为客户端代码是可以被逆向的。
///
/// 但"别把密码明文写进文件"这件事，假实现里也应该守住 ——
/// 养成习惯比图省事重要。
enum PasswordDigest {

    static func makeSalt() -> String {
        UUID().uuidString
    }

    static func hash(_ password: String, salt: String) -> String {
        let data = Data((password + salt).utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
