import SwiftUI

/// 登录状态的「总管家」。
///
/// 和 `ChatStore` 一样：界面只读它的数据、只调它的方法，
/// 不关心底下是真服务器还是假数据。
///
/// @Observable 让界面自动跟着刷新 —— 登录成功后 `account` 一变，
/// 那张登录页就会自己消失。
@Observable
final class AuthStore {

    /// 当前登录的账号。nil 表示未登录。
    private(set) var account: Account?

    /// 正在跟服务器打交道（界面据此显示转圈、禁用按钮）
    private(set) var isWorking = false

    /// 出错时要显示给用户的一句话。
    /// 存成字符串而不是 Error，是因为界面只需要显示它 ——
    /// 让界面去判断错误类型，等于把业务逻辑漏进了视图层。
    var errorMessage: String?

    private let service: AuthService

    init(service: AuthService = AppServices.makeAuthService()) {
        self.service = service
        // 启动时同步读一次本地会话 —— 上次登录过就直接进去，不用再输一遍密码
        self.account = service.currentAccount()
    }

    var isSignedIn: Bool { account != nil }

    /// 点邮件里的确认链接跳回来时要告诉用户的话。nil 表示不显示。
    var linkMessage: String?

    /// 登录状态能不能记住（记不住时界面要如实告诉用户）
    var isSessionPersisted: Bool { service.isSessionPersisted }

    /// 改用户名。
    ///
    /// 和改昵称分开，因为它的失败理由完全不同（被占用 / 格式 / 保留字），
    /// 那些理由要原样交给界面显示。
    func updateUsername(_ username: String) async -> Bool {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            account = try await service.updateUsername(username)
            Haptics.success()
            return true
        } catch {
            errorMessage = describe(error)
            Haptics.warning()
            return false
        }
    }

    /// 改昵称、简介、头像色。
    func updateProfile(displayName: String, bio: String, avatarSeed: Int) async -> Bool {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            account = try await service.updateProfile(displayName: displayName,
                                                      bio: bio,
                                                      avatarSeed: avatarSeed)
            Haptics.success()
            return true
        } catch {
            errorMessage = describe(error)
            Haptics.warning()
            return false
        }
    }

    // MARK: - 从邮件链接跳回来

    /// 处理"用户在邮件里点了确认链接，iOS 把 App 打开"这件事。
    ///
    /// 【两种结果都要处理好】
    ///
    /// 链接里**带登录凭证**（通常是这样）→ 直接帮他登录，连密码都不用输。
    /// 链接里**没有凭证**（或者凭证已经失效）→ 也要告诉他"验证成功了"，
    ///   让他手动登录一次就行 —— **绝不能让他以为失败又重来一遍注册**。
    func handleLink(_ url: URL) async {
        AppLog.info(.network, "handleLink 收到：\(url.absoluteString)（scheme=\(url.scheme ?? "无")）")
        guard url.scheme == AppLink.scheme else {
            AppLog.info(.network, "scheme 不匹配，忽略")
            return
        }

        isWorking = true
        defer { isWorking = false }

        if let tokens = AppLink.tokens(from: url),
           let adopted = await service.adoptSession(accessToken: tokens.access,
                                                    refreshToken: tokens.refresh) {
            account = adopted
            linkMessage = "邮箱验证成功，已经帮你登录了。"
            Haptics.success()
            return
        }

        linkMessage = "邮箱验证成功，现在可以用这个邮箱和密码登录了。"
        Haptics.success()
    }

    // MARK: - 动作

    func signIn(email: String, password: String) async {
        await run { try await self.service.signIn(email: email, password: password) }
    }

    func signUp(email: String, password: String, confirmPassword: String) async {
        // 两次密码一致这件事在客户端先挡一道 ——
        // 没必要为了这个跑一趟网络，用户也不该白等 700 毫秒才知道自己打错了
        guard password == confirmPassword else {
            errorMessage = AuthError.passwordMismatch.errorDescription
            return
        }
        await run { try await self.service.signUp(email: email, password: password) }
    }

    func signOut() async {
        await service.signOut()
        account = nil
        errorMessage = nil
    }

    func sendPasswordReset(email: String) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await service.sendPasswordReset(email: email)
            errorMessage = nil
        } catch {
            errorMessage = describe(error)
        }
    }

    // MARK: - 内部

    /// 把"调用服务 → 设置账号 / 把错误翻译成人话"这套动作收在一处。
    /// 三个动作（注册/登录/重置）都是这个形状，写三遍只会让它们慢慢长歪。
    private func run(_ work: @escaping () async throws -> Account) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            account = try await work()
            Haptics.success()
        } catch {
            errorMessage = describe(error)
            Haptics.warning()
        }
    }

    /// 把任意错误翻译成一句能给用户看的话
    private func describe(_ error: Error) -> String {
        // 【为什么第一件事是"用它自己的说明"】
        //
        // AuthError 和 SupabaseError 都实现了 LocalizedError ——
        // 也就是说它们**自带一句给人看的中文说明**，甚至带着服务器的原话。
        //
        // 我原来的写法只认 AuthError，于是所有 SupabaseError 都被吞成了
        // "出了点问题，再试一次。" —— 一句没有任何信息量的废话。
        //
        // 这个 bug 的代价很大：用户注册失败时，真正的原因
        //（比如"发确认邮件失败"）明明就在错误对象里，我们却把它扔了。
        if let described = (error as? LocalizedError)?.errorDescription,
           !described.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return described
        }
        if (error as NSError).domain == NSURLErrorDomain {
            return AuthError.network.errorDescription ?? "网络好像不太顺，等一下再试。"
        }
        return "出了点问题，再试一次。"
    }
}
