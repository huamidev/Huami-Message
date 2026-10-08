import Foundation

/// 假数据版的登录服务。
///
/// 【它存在的意义】
///
/// 让你在**还没注册 Supabase 之前**就能把整条登录链路跑通：
/// 注册 → 登录 → 退出 → 再登录。界面、状态管理、错误提示全都能测。
///
/// 等接上 Supabase，只需要写一个 `SupabaseAuthService` 实现同一个协议，
/// **界面代码一行都不用改**。
///
/// ⚠️ 它把账号存在 UserDefaults 里，密码存的是加盐摘要（不是明文），
/// 但这**没有任何真实安全性** —— 客户端代码可以被逆向，
/// 真正的密码校验永远在服务器上做。这里只是别养成明文存密码的坏习惯。
final class MockAuthService: AuthService {

    private let store = UserDefaults.standard

    private let accountsKey = "mock.accounts"
    private let sessionKey = "mock.session"

    /// 一条账号记录：账号信息 + 加盐后的密码摘要
    private struct Record: Codable {
        var account: Account
        var salt: String
        var digest: String
    }

    // MARK: - 读

    func currentAccount() -> Account? {
        guard let data = store.data(forKey: sessionKey) else { return nil }
        return try? JSONDecoder().decode(Account.self, from: data)
    }

    // MARK: - 注册

    func signUp(email: String, password: String) async throws -> Account {
        try await simulateNetwork()

        let normalized = normalize(email)
        guard AuthRules.isValidEmail(normalized) else { throw AuthError.invalidEmail }
        guard AuthRules.isValidPassword(password) else { throw AuthError.weakPassword }

        var records = loadRecords()
        guard records[normalized] == nil else { throw AuthError.emailAlreadyUsed }

        let salt = PasswordDigest.makeSalt()
        let account = Account(
            id: UUID(),
            email: normalized,
            displayName: Account.name(from: normalized),
            avatarSeed: Int.random(in: 0..<6),
            inviteCode: AuthRules.makeInviteCode()
        )
        records[normalized] = Record(
            account: account,
            salt: salt,
            digest: PasswordDigest.hash(password, salt: salt)
        )
        save(records)
        saveSession(account)
        return account
    }

    // MARK: - 登录

    func signIn(email: String, password: String) async throws -> Account {
        try await simulateNetwork()

        let normalized = normalize(email)
        guard AuthRules.isValidEmail(normalized) else { throw AuthError.invalidEmail }

        // 注意：邮箱不存在和密码不对，返回的是**同一个错误**。
        // 这不是偷懒 —— 分开提示等于告诉别人"这个邮箱注册过"，
        // 那是一种可以被用来探测用户的信息泄露。
        guard let record = loadRecords()[normalized],
              PasswordDigest.hash(password, salt: record.salt) == record.digest else {
            throw AuthError.wrongCredentials
        }

        saveSession(record.account)
        return record.account
    }

    func updateProfile(displayName: String, bio: String, avatarSeed: Int) async throws -> Account {
        try await simulateNetwork()
        guard var account = currentAccount() else { throw AuthError.notSignedIn }

        account.displayName = displayName
        account.bio = bio
        account.avatarSeed = avatarSeed

        saveSession(account)
        var records = loadRecords()
        if var record = records[account.email.lowercased()] {
            record.account = account
            records[account.email.lowercased()] = record
            save(records)
        }
        return account
    }

    /// 假实现没有邮件链接这回事
    func adoptSession(accessToken: String, refreshToken: String?) async -> Account? { nil }

    // MARK: - 退出

    func signOut() async {
        store.removeObject(forKey: sessionKey)
    }

    // MARK: - 重置密码

    func sendPasswordReset(email: String) async throws {
        try await simulateNetwork()
        // 假实现不会真的发邮件 —— 说清楚，别让用户对着界面干等
        throw AuthError.unknown("还没有接邮件服务，暂时发不了重置邮件。接上之后这里就能用了。")
    }

    // MARK: - 内部

    private func normalize(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// 假装网络要花一点时间。
    /// 加它是为了让"加载中"的界面状态真的能被看到 ——
    /// 如果假实现是瞬间返回的，等接上真网络才发现转圈动画有问题就晚了。
    private func simulateNetwork() async throws {
        try? await Task.sleep(for: .milliseconds(700))
    }

    private func loadRecords() -> [String: Record] {
        guard let data = store.data(forKey: accountsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: Record].self, from: data)) ?? [:]
    }

    private func save(_ records: [String: Record]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        store.set(data, forKey: accountsKey)
    }

    private func saveSession(_ account: Account) {
        guard let data = try? JSONEncoder().encode(account) else { return }
        store.set(data, forKey: sessionKey)
    }
}
