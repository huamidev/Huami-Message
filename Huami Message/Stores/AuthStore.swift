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

    init(service: AuthService = MockAuthService()) {
        self.service = service
        // 启动时同步读一次本地会话 —— 上次登录过就直接进去，不用再输一遍密码
        self.account = service.currentAccount()
    }

    var isSignedIn: Bool { account != nil }

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
        if let authError = error as? AuthError {
            return authError.errorDescription ?? "出了点问题，再试一次。"
        }
        if (error as NSError).domain == NSURLErrorDomain {
            return AuthError.network.errorDescription ?? "网络好像不太顺，等一下再试。"
        }
        return "出了点问题，再试一次。"
    }
}
