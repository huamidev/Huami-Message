import Foundation

/// 这台手机上登录过的账号。
///
/// 【为什么要有它】
///
/// 现在退出登录之后就只剩一个邮箱输入框，得重新打一遍邮箱和密码。
/// 但用户其实只是在**自己的两个号之间来回切**（工作号 / 私人号），
/// 每次都重打密码很烦 —— 而且手机上打字本来就慢。
///
/// 所以退出登录**不等于**把这个号忘掉：会话存在钥匙串里，
/// 下次在登录页直接点一下就回来了。
///
/// 【为什么存在钥匙串，而不是 UserDefaults】
///
/// 这里存的是 **refresh token** —— 拿到它就等于拿到了这个账号。
/// UserDefaults 是明文 plist，越狱设备或者备份里都能直接读出来。
/// 钥匙串有系统级加密，这是它该待的地方。
///
/// 【和账号数据隔离的关系】
///
/// 本地聊天数据已经按「账号 ID」分开了（见 StoredFriend.ownerIDString）。
/// 所以切换账号之后，看到的是**那个账号自己的**聊天记录，
/// 不会串台 —— 这也是这个功能敢做的前提。
@MainActor
@Observable
final class AccountVault {

    static let shared = AccountVault()

    /// 存过的账号，最近登录的排在最前。
    private(set) var accounts: [SavedAccount] = []

    private static let storageKey = "huami.saved-accounts"

    private init() { load() }

    /// 登录成功后调一次。
    func remember(_ account: Account,
                  accessToken: String,
                  refreshToken: String?) {
        // 同一个账号只留一条（重新登录会刷新 token）
        var list = accounts.filter { $0.id != account.id }
        list.insert(SavedAccount(id: account.id,
                                 email: account.email,
                                 displayName: account.displayName,
                                 username: account.username,
                                 avatarSeed: account.avatarSeed,
                                 accessToken: accessToken,
                                 refreshToken: refreshToken,
                                 savedAt: Date()), at: 0)
        accounts = list
        persist()
    }

    /// 重新登录成功了，刷新一下这条记录里的 token。
    func refreshTokens(for id: UUID, accessToken: String, refreshToken: String?) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[index].accessToken = accessToken
        accounts[index].refreshToken = refreshToken
        accounts[index].savedAt = Date()
        persist()
    }

    /// 改名 / 换头像之后同步一下，列表上显示的就是最新的。
    func update(_ account: Account) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[index].displayName = account.displayName
        accounts[index].username = account.username
        accounts[index].email = account.email
        accounts[index].avatarSeed = account.avatarSeed
        persist()
    }

    /// 用户明确说"别再记住这个号了"才调它。
    ///
    /// ⚠️ 普通的"退出登录"**不要**调 —— 那正是我们想记住的东西。
    func forget(_ id: UUID) {
        accounts.removeAll { $0.id == id }
        persist()
    }

    // MARK: - 落盘

    private func load() {
        #if DEBUG
        // 开发自检：模拟器的钥匙串写入会失败（未签名构建 -34018），
        // 所以账号列表在模拟器上永远是空的，这屏根本看不到。
        // 用启动参数塞两条假的，专门用来看布局。
        if DevFlags.seedAccounts && accounts.isEmpty {
            accounts = [
                SavedAccount(id: UUID(), email: "huamidev@gmail.com",
                             displayName: "huami", username: "huami", avatarSeed: 3,
                             accessToken: "dev", refreshToken: "dev",
                             savedAt: Date()),
                SavedAccount(id: UUID(), email: "huamidev888@gmail.com",
                             displayName: "huami888", username: "test002", avatarSeed: 7,
                             accessToken: "dev", refreshToken: "dev",
                             savedAt: Date().addingTimeInterval(-3600)),
            ]
            return
        }
        #endif
        guard let data = Keychain.load(Self.storageKey),
              let decoded = try? JSONDecoder().decode([SavedAccount].self, from: data)
        else { return }
        accounts = decoded.sorted { $0.savedAt > $1.savedAt }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        _ = Keychain.save(data, for: Self.storageKey)
    }
}

/// 存下来的一个账号。
///
/// 字段都是"登录页上要显示的东西" + "换回这个账号需要的东西"。
/// 不多存 —— 存多了就多一份泄漏面，而这里存的是 token。
struct SavedAccount: Codable, Identifiable, Hashable {
    let id: UUID
    var email: String
    var displayName: String
    var username: String
    var avatarSeed: Int
    var accessToken: String
    var refreshToken: String?
    var savedAt: Date

    /// 头像上显示的那个字
    var initial: String { String(displayName.prefix(1)) }

    /// 列表第二行：有用户名就显示 @用户名，否则退回邮箱
    var subtitle: String { username.isEmpty ? email : "@" + username }
}
