import Foundation

// ============================================================================
// 真·登录服务（Supabase）
// ============================================================================
//
// 和 `MockAuthService` 实现的是**同一个协议** ——
// 所以界面代码一行都不用改，只是后面换了个"真电"。
//
// 用到的三个接口：
//   POST /auth/v1/signup                      注册
//   POST /auth/v1/token?grant_type=password   登录
//   POST /auth/v1/logout                      退出
//   POST /auth/v1/recover                     发重置密码的邮件
//
// 再加上一个数据库查询，把用户档案（昵称、用户名）读出来。
//
// ============================================================================

final class SupabaseAuthService: AuthService {

    private let client: SupabaseClient

    /// 登录凭证有没有成功存进钥匙串。
    /// 存不进去时置为 false，界面会告诉用户"下次打开要重新登录"。
    private(set) var isSessionPersisted = true

    /// **内存里**的当前账号。
    ///
    /// 【为什么不能只靠钥匙串】
    ///
    /// 钥匙串在某些环境下写不进去 —— 比如没有正确签名的开发构建，
    /// `SecItemAdd` 会返回 -34018（缺少权限）。
    ///
    /// 那种情况下 App 照样能用（内存里有账号、请求也带着凭证），
    /// 但如果"改资料"这种操作也去**读钥匙串**拿当前账号，
    /// 就会莫名其妙地报"你还没有登录" —— 用户明明就在界面上看着自己。
    ///
    /// 所以改成：**内存优先，钥匙串只负责"下次启动还能记得"。**
    /// 这也是我自己踩出来的：改简介一直失败，
    /// 查了半天才发现请求根本没发出去，卡在读钥匙串那一步。
    private var cachedAccount: Account?

    /// 钥匙串里存这条会话用的键名
    private static let sessionKey = "supabase.session"

    init(client: SupabaseClient) {
        self.client = client

        // 启动时把上次的会话接回来。
        // 这一步是同步的（只是读钥匙串），所以 App 打开就能直接进去，
        // 不会先闪一下登录页再跳走。
        if let session = Self.loadSession() {
            client.setSession(accessToken: session.accessToken, userID: session.account.id)
        }
    }

    // MARK: - 当前账号

    func currentAccount() -> Account? {
        if let cachedAccount { return cachedAccount }
        if let session = Self.loadSession() {
            cachedAccount = session.account
            return session.account
        }
        return nil
    }

    // MARK: - 注册

    func signUp(email: String, password: String) async throws -> Account {
        let normalized = normalize(email)
        // 本地先挡一道：没必要为了"邮箱少个 @" 跑一趟网络，用户也不该白等
        guard AuthRules.isValidEmail(normalized) else { throw AuthError.invalidEmail }
        guard AuthRules.isValidPassword(password) else { throw AuthError.weakPassword }

        let response: AuthResponse
        do {
            response = try await client.post(
                "/auth/v1/signup",
                // 告诉服务器：用户在邮件里点确认之后，**跳回 App**，不要跳到网页。
                // 这个地址必须在 Supabase 的 Redirect URLs 白名单里，否则会被忽略。
                query: [URLQueryItem(name: "redirect_to", value: AppLink.confirmURL)],
                body: Credentials(email: normalized, password: password),
                as: AuthResponse.self
            )
        } catch {
            throw Self.translate(error)
        }

        // ⚠️ 如果项目设置里开着「Confirm email」，注册接口**只返回用户、不返回会话** ——
        //    用户必须先去点邮件里的链接才能登录。
        //
        //    我们的设计是**关掉邮箱验证**（原因见 docs/12-账号与登录.md：
        //    Supabase 免费版自带的邮件服务限流极严，一小时只发得了几封）。
        //    但这里还是要处理这种情况，不能假设设置一定按我们想的来。
        guard let token = response.accessToken, let user = response.user else {
            throw AuthError.emailConfirmationRequired
        }

        client.setSession(accessToken: token, userID: user.id)
        return try await finishSignIn(user: user, accessToken: token, refreshToken: response.refreshToken)
    }

    // MARK: - 登录

    func signIn(email: String, password: String) async throws -> Account {
        let normalized = normalize(email)
        guard AuthRules.isValidEmail(normalized) else { throw AuthError.invalidEmail }

        let response: AuthResponse
        do {
            response = try await client.post(
                "/auth/v1/token",
                query: [URLQueryItem(name: "grant_type", value: "password")],
                body: Credentials(email: normalized, password: password),
                as: AuthResponse.self
            )
        } catch {
            throw Self.translate(error)
        }

        guard let token = response.accessToken, let user = response.user else {
            throw AuthError.wrongCredentials
        }

        client.setSession(accessToken: token, userID: user.id)
        return try await finishSignIn(user: user, accessToken: token, refreshToken: response.refreshToken)
    }

    // MARK: - 用邮件链接里的凭证登录

    func adoptSession(accessToken: String, refreshToken: String?) async -> Account? {
        // 先把凭证装上 —— 接下来的请求要拿它去问服务器"我是谁"。
        // 注意 userID 先留空：现在还不知道，靠下面的请求问出来。
        client.setSession(accessToken: accessToken, userID: nil)

        guard let user = try? await client.get("/auth/v1/user", as: AuthUser.self) else {
            // 凭证无效或过期：清干净，让用户手动登录一次
            client.setSession(accessToken: nil, userID: nil)
            return nil
        }

        client.setSession(accessToken: accessToken, userID: user.id)
        return try? await finishSignIn(user: user,
                                       accessToken: accessToken,
                                       refreshToken: refreshToken)
    }

    // MARK: - 改用户名

    func updateUsername(_ username: String) async throws -> Account {
        let cleaned = Username.normalize(username)

        // 先在本地拦一道：格式不对根本不用发请求。
        // 快是一方面，更重要的是**错误信息可以写得具体**
        //（"至少要 5 位"比服务器那句约束名有用得多）。
        if let problem = Username.problem(with: cleaned) {
            throw AuthError.unknown(problem)
        }

        guard let current = currentAccount() else { throw AuthError.notSignedIn }

        let rows: [ProfileRow]
        do {
            rows = try await client.patch(
                "/rest/v1/profiles",
                query: [URLQueryItem(name: "id",
                                     value: "eq.\(current.id.uuidString.lowercased())")],
                body: UsernamePatch(username: cleaned),
                prefer: "return=representation",
                as: [ProfileRow].self
            )
        } catch {
            throw Self.translateUsernameError(error)
        }

        let updated = Account(
            id: current.id,
            email: current.email,
            displayName: current.displayName,
            avatarSeed: current.avatarSeed,
            bio: current.bio,
            username: rows.first?.username ?? cleaned
        )
        cachedAccount = updated
        if var session = Self.loadSession() {
            session.account = updated
            saveSession(session)
        }
        return updated
    }

    /// 把数据库的报错翻译成"用户能照做的一句话"。
    ///
    /// 【为什么要专门做这件事】
    ///
    /// 用户名有三种完全不同的失败方式，而数据库只会给
    /// "duplicate key value violates unique constraint ..." 这种话：
    ///   · 被占用 —— 换一个名字
    ///   · 是保留字 —— 换个别的（我们的触发器已经写好了人话，直接透传）
    ///   · 格式不对 —— 按理说本地就拦住了，这里是兜底
    ///
    /// 不翻译的话，用户看到的是约束名，等于没说。
    private static func translateUsernameError(_ error: Error) -> Error {
        guard case SupabaseError.http(let status, let message) = error else { return error }

        // 409 / 23505 都是"唯一约束冲突"
        if status == 409 || message.contains("23505")
            || message.contains("duplicate key") {
            return AuthError.unknown("这个名字已经有人用了，换一个吧。")
        }
        if message.contains("保留") {
            return AuthError.unknown(message)      // 触发器已经说了人话
        }
        if message.contains("profiles_username_format")
            || message.contains("check constraint") {
            return AuthError.unknown("用户名只能是英文字母和数字，字母开头，5 到 20 位。")
        }
        return error
    }

    // MARK: - 改资料

    func updateProfile(displayName: String, bio: String, avatarSeed: Int) async throws -> Account {
        guard let current = currentAccount() else { throw AuthError.notSignedIn }

        let rows: [ProfileRow]
        do {
            rows = try await client.patch(
                "/rest/v1/profiles",
                query: [URLQueryItem(name: "id",
                                     value: "eq.\(current.id.uuidString.lowercased())")],
                body: ProfilePatch(displayName: displayName, bio: bio, avatarSeed: avatarSeed),
                prefer: "return=representation",
                as: [ProfileRow].self
            )
        } catch {
            throw Self.translateProfileError(error)
        }

        let updated = Account(
            id: current.id,
            email: current.email,
            displayName: displayName,
            avatarSeed: avatarSeed,
            bio: bio,
            username: rows.first?.username ?? current.username
        )

        cachedAccount = updated

        // 会话里存的那份也要更新 —— 否则下次启动又从本地读回旧昵称
        if var session = Self.loadSession() {
            session.account = updated
            saveSession(session)
        }
        return updated
    }

    /// 把"数据库里没有 bio 这一列"翻译成一句能照做的话。
    ///
    /// 这个情况**一定会发生**：简介是后加的功能，需要用户在 SQL Editor 里
    /// 跑一句 `alter table ... add column bio`。在他跑之前，
    /// PostgREST 会回一句 "column profiles.bio does not exist" ——
    /// 让用户看到这个等于没说。
    private static func translateProfileError(_ error: Error) -> Error {
        guard case SupabaseError.http(_, let message) = error else { return error }
        if message.contains("bio") && message.contains("does not exist") {
            return AuthError.unknown(
                "数据库里还没有「简介」这一列。\n\n"
                + "请在 Supabase 的 SQL Editor 里跑一句：\n"
                + "alter table public.profiles add column if not exists bio text not null default '';"
            )
        }
        return error
    }

    // MARK: - 退出

    func signOut() async {
        // 先告诉服务器作废这个 token。
        // 失败也无所谓 —— 本地照样清干净，用户要的是"我退出了"。
        try? await client.post("/auth/v1/logout", body: EmptyBody())
        client.setSession(accessToken: nil, userID: nil)
        cachedAccount = nil
        Keychain.delete(Self.sessionKey)
    }

    // MARK: - 重置密码

    func sendPasswordReset(email: String) async throws {
        let normalized = normalize(email)
        guard AuthRules.isValidEmail(normalized) else { throw AuthError.invalidEmail }
        do {
            try await client.post("/auth/v1/recover", body: EmailOnly(email: normalized))
        } catch {
            let translated = Self.translate(error)
            // 为了不泄露"这个邮箱注册过没有"，不管成功失败都当成功处理。
            // 唯一的例外是邮箱格式不对 —— 那个是用户的笔误，说了没坏处。
            if case AuthError.invalidEmail = translated { throw translated }
            AppLog.info(.network, "重置密码邮件请求已发出（服务器是否真的发了不告诉用户）")
        }
    }

    // MARK: - 内部

    private func normalize(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// 拿到凭证之后要做的事：读档案 → 存会话 → 返回账号
    private func finishSignIn(user: AuthUser,
                              accessToken: String,
                              refreshToken: String?) async throws -> Account {
        let email = user.email ?? ""

        // 档案（昵称、用户名）是**数据库触发器**在注册时自动建的。
        // 理论上一定存在，但万一没有（比如 schema.sql 没跑全），
        // 不该让整个登录失败 —— 用默认值先让用户进去，问题记在日志里。
        let profile = try? await fetchProfile(userID: user.id)
        if profile == nil {
            AppLog.error(.network, "读不到用户档案，可能数据库触发器没建好。用户 id=\(user.id)")
        }

        let account = Account(
            id: user.id,
            email: email,
            displayName: profile?.displayName ?? Account.name(from: email),
            avatarSeed: profile?.avatarSeed ?? 0,
            bio: profile?.bio ?? "",
            username: profile?.username ?? ""
        )

        cachedAccount = account
        saveSession(StoredSession(accessToken: accessToken,
                                  refreshToken: refreshToken,
                                  account: account))
        AppLog.info(.network, "登录成功：\(account.displayName)")
        return account
    }

    private func fetchProfile(userID: UUID) async throws -> ProfileRow? {
        let rows: [ProfileRow] = try await client.get(
            "/rest/v1/profiles",
            query: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "id", value: "eq.\(userID.uuidString.lowercased())"),
                URLQueryItem(name: "limit", value: "1"),
            ],
            as: [ProfileRow].self
        )
        return rows.first
    }

    /// 把服务器返回的错误翻成用户看得懂的话。
    ///
    /// 【为什么要做这一层】
    /// Supabase 返回的是英文技术描述，比如 "Invalid login credentials"、
    /// "User already registered"。直接显示给中文用户等于没说。
    private static func translate(_ error: Error) -> Error {
        guard case SupabaseError.http(let status, let message) = error else { return error }
        let lower = message.lowercased()

        // ⚠️ 顺序有讲究：这条必须在下面那些通用判断之前。
        //    "invalid login credentials" 也带 400，先被通用分支吃掉就翻错了。
        // 三种写法都要认：
        //   · "invalid login credentials" 是**消息文本**（真服务器返回的就是这个）
        //   · "invalid_grant"      是 OAuth 标准错误码
        //   · "invalid_credentials" 是真服务器返回的 error_code 字段
        if lower.contains("invalid login credentials")
            || lower.contains("invalid_grant")
            || lower.contains("invalid_credentials") {
            return AuthError.wrongCredentials
        }
        if lower.contains("already registered") || lower.contains("already been registered")
            || lower.contains("user already exists") {
            return AuthError.emailAlreadyUsed
        }
        if lower.contains("password") && (status == 400 || status == 422) {
            return AuthError.weakPassword
        }
        if lower.contains("email") && (status == 400 || status == 422) {
            return AuthError.invalidEmail
        }
        if lower.contains("rate limit") || status == 429 {
            return AuthError.unknown("请求太频繁了，等一分钟再试。")
        }
        return error
    }

    // MARK: - 会话的存取

    /// 存在钥匙串里的会话。
    /// 只存三样东西：凭证、刷新凭证、账号信息（用来开屏直接显示，不用再问服务器）。
    private struct StoredSession: Codable {
        var accessToken: String
        var refreshToken: String?
        var account: Account
    }

    private static func loadSession() -> StoredSession? {
        guard let data = Keychain.load(sessionKey) else { return nil }
        return try? JSONDecoder().decode(StoredSession.self, from: data)
    }

    /// 存会话。**会记录成功与否** —— 存不进去不能让用户蒙在鼓里。
    private func saveSession(_ session: StoredSession) {
        guard let data = try? JSONEncoder().encode(session) else {
            isSessionPersisted = false
            return
        }
        isSessionPersisted = Keychain.save(data, for: Self.sessionKey)
        if !isSessionPersisted {
            AppLog.error(.network, "登录凭证没能存进钥匙串，这台设备上下次打开需要重新登录")
        }
    }
}

// ============================================================================
// 服务器返回的数据形状
// ============================================================================

private struct Credentials: Encodable {
    let email: String
    let password: String
}

private struct EmailOnly: Encodable {
    let email: String
}

private struct EmptyBody: Encodable {}

/// 改资料时发给服务器的字段。
/// 用 convertToSnakeCase 会自动变成 display_name / bio / avatar_seed。
/// 改用户名时发给服务器的字段。
/// 只发这一个 —— **不要顺手把别的字段也发上去**：
/// 并发改资料时，把没变的字段一起发会互相覆盖。
private struct UsernamePatch: Encodable {
    let username: String
}

private struct ProfilePatch: Encodable {
    let displayName: String
    let bio: String
    let avatarSeed: Int
}

private struct AuthUser: Decodable {
    let id: UUID
    let email: String?
}

/// 登录 / 注册接口的返回。
/// `accessToken` 是可选的 —— 开了邮箱验证时注册接口不会返回会话。
private struct AuthResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let user: AuthUser?
}

// `ProfileRow` 定义在 SupabaseChatService.swift —— 两个服务共用一份。
