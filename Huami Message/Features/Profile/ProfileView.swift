import SwiftUI

/// 「我」页。
///
/// 第一版这里只是个骨架，但有**两个东西现在就要放进来**，
/// 因为它们是上架审核的硬要求，晚做会返工：
///
///   1. 「隐私」说明：写清 AI 润色到底会把什么发出去。
///      审核会看，用户信任也靠它。
///
///   2. 「删除账号」入口：只要有注册功能，苹果就强制要求 App 内能删号。
///      （App Store 审核指南 5.1.1(v)，2022 年 6 月起执行）
///      这是最容易被忽略、又最容易被拒的一条。先把位置占住，
///      第 1 步接入账号后把它接上。
struct ProfileView: View {

    @Environment(ChatStore.self) private var store
    @Environment(AuthStore.self) private var auth

    /// 正在查看的法律文档（隐私政策 / 服务条款）
    @State private var showDocument: LegalDocument?

    /// 是否正在确认"删除账号"
    @State private var showDeleteAccount = false

    /// 是否正在编辑资料
    @State private var showEditProfile = false

    /// 是否打开「API 接入」

    /// 刚复制过用户名（用来把图标变成对勾）
    @State private var copiedUsername = false
    @State private var showAPIAccess = false

    var body: some View {
        NavigationStack {
            AppPage {
                ScrollView {
                    VStack(spacing: 16) {
                        identityCard
                        privacyCard
                        settingsCard
                        legalCard
                        aboutCard
                    }
                    .padding(16)
                    .padding(.bottom, 96)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("我")
        }
        .sheet(item: $showDocument) { document in
            LegalDocumentView(document: document)
        }
        // 删除是不可撤销的，必须再问一次 —— 而且要说清楚删掉什么、能不能恢复。
        // 这是 App Store 审核指南 5.1.1(v) 的硬性要求：
        // **只要 App 能注册账号，就必须能在 App 内删掉它。**
        // 环境要显式传进弹窗（这个坑踩过三次了）
        .task {
            if DevFlags.openAPI {
                try? await Task.sleep(for: .seconds(2))
                showAPIAccess = true
            }
            guard DevFlags.openEditProfile else { return }
            try? await Task.sleep(for: .seconds(2))
            showEditProfile = true
        }
        .sheet(isPresented: $showAPIAccess) {
            APIAccessView()
        }
        .sheet(isPresented: $showEditProfile) {
            if let account = auth.account {
                EditProfileSheet(account: account)
                    .environment(auth)
            }
        }
        .confirmationDialog("删除账号和全部数据？",
                            isPresented: $showDeleteAccount, titleVisibility: .visible) {
            Button("永久删除", role: .destructive) {
                withAnimation(.snappy) { store.deleteEverything() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会删掉你所有的聊天记录、好友和举报记录。删除后无法恢复。\n\n（接上服务器之后，这里还会同时删除服务器上的数据。）")
        }
        // 开发用：带 -legalDoc terms 直接打开对应文档
        .task {
            switch DevFlags.legalDoc {
            case "privacy": showDocument = .privacy
            case "terms":   showDocument = .terms
            default:        break
            }
        }
    }

    // MARK: - 身份

    private var identityCard: some View {
        // 排版照 Telegram 的「我」页面：
        //   头像居中 → 名字 → 简介 → 次要信息（邮箱、邀请码）→ 编辑按钮
        //
        // 为什么不把邮箱放在名字下面当主信息：
        // **用户认同的是"我叫什么"，不是"我注册时填了哪个邮箱"**。
        // 邮箱只是"这台设备上登录的是哪个账号"，该退到次要位置。
        VStack(spacing: 12) {
            Avatar(initial: displayInitial, seed: auth.account?.avatarSeed ?? 0, size: 88)
                .onTapGesture {
                    Haptics.tap()
                    showEditProfile = true
                }

            VStack(spacing: 6) {
                Text(auth.account?.displayName ?? "未登录")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text(bioText)
                    .font(.system(size: 13.5))
                    .foregroundStyle(hasBio ? Theme.textSecondary : Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)

                // 用户名：**别人的入口**，所以放在名字下面最显眼处，
                // 点一下就能复制走，好发给别人
                if let username = auth.account?.username, !username.isEmpty {
                    Button {
                        Haptics.tap()
                        UIPasteboard.general.string = username
                        copiedUsername = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("@\(username)")
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                            Image(systemName: copiedUsername ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(copiedUsername ? Theme.mint : Theme.accent)
                    }
                    .buttonStyle(.plain)
                }

                Text(auth.account?.email ?? "")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                if let code = auth.account?.inviteCode {
                    HStack(spacing: 5) {
                        Image(systemName: "ticket.fill").font(.system(size: 10))
                        Text(code)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Theme.accentSoft, in: Capsule())
                }

                Button {
                    Haptics.tap()
                    showEditProfile = true
                } label: {
                    Text("编辑资料")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Theme.accentSoft, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .card()
        .overlay(alignment: .bottom) {
            // 钥匙串写不进去时（开发构建常见），如实说明。
            // 让用户自己发现"怎么每次都要重新登录"是最差的做法。
            if auth.isSignedIn && !auth.isSessionPersisted {
                Text("⚠️ 这台设备上没能保存登录状态，下次打开需要重新登录")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.warning)
                    .padding(.bottom, 5)
            }
        }
    }

    /// 简介。没写的时候给一句引导，而不是留一片空白
    private var bioText: String {
        hasBio ? (auth.account?.bio ?? "") : "点下面的「编辑资料」写一句介绍"
    }

    private var hasBio: Bool {
        !(auth.account?.bio ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 头像上显示那个字
    private var displayInitial: String {
        guard let name = auth.account?.displayName, let first = name.first else { return "?" }
        return String(first).uppercased()
    }

    // MARK: - 隐私（重要）

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("隐私", icon: "lock.shield.fill", tint: Theme.mint)

            privacyRow(
                "AI 润色会发送什么",
                "只发送你正在打的那一句话，不发送你和好友的聊天记录。"
            )
            privacyRow(
                "小助手会看到什么",
                "默认打开时，对方每发来一条消息，App 会把最近 10 条发给 AI 服务商，"
                + "用来给出判断——也就是说你朋友的消息会被自动发出去。"
                + "聊天页右上角的菜单里可以随时关掉，关掉之后就只在你主动点时才发送。"
            )
            privacyRow(
                "聊天记录",
                "只存在你的手机和你自己的服务器账号里。"
            )
        }
        .padding(16)
        .card()
    }

    // MARK: - 设置

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("设置", icon: "gearshape.fill", tint: Theme.accent)
                .padding(.bottom, 12)

            settingRow("AI 服务商", value: "DeepSeek", enabled: false)
            divider

            // 「API 接入」放在这里，而不是埋进隐私那一段：
            // 它不是一个"我们的承诺"，而是**用户自己的一个选择** ——
            // 想用自己的 AI 账号、花自己的钱，从这里进。
            Button {
                Haptics.tap()
                showAPIAccess = true
            } label: {
                settingRow("API 接入",
                           value: PersonalAIKey.isSet ? "用自己的密钥" : "用默认的",
                           enabled: true)
            }
            .buttonStyle(.plain)
            divider
            Button {
                Haptics.warning()
                showDeleteAccount = true
            } label: {
                settingRow("删除账号", value: "", enabled: false, showsChevron: true)
            }
            .buttonStyle(.plain)
            divider
            settingRow("举报与屏蔽", value: "待接入", enabled: false)
            divider
            Button {
                // 用 warning 而不是 tap：退出是个"有后果"的动作，
                // 震动要能让人感觉到"刚才发生了一件事"。
                Haptics.warning()
                Task { await auth.signOut() }
            } label: {
                HStack {
                    Text("退出登录")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.danger)
                    Spacer()
                }
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .card()
    }

    /// 法律文档入口。
    /// 放在这里而不是藏进"设置 → 关于 → 更多"里 ——
    /// **审核员和用户都应该能两步之内找到它。**
    private var legalCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("法律", icon: "doc.text.fill", tint: Theme.textSecondary)
                .padding(.bottom, 12)

            ForEach(LegalDocument.allCases) { document in
                Button {
                    Haptics.tap()
                    showDocument = document
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(document.title)
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.textPrimary)
                            Text(document.summary)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textTertiary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if document != LegalDocument.allCases.last { divider }
            }
        }
        .padding(16)
        .card()
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("关于", icon: "info.circle.fill", tint: Theme.warning)

            Text("Huami Message")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.textPrimary)

            Text("这是一个「帮你把话说好」的工具，不是一个普通的聊天软件。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            Text("版本 1.0 · 开发中（第 0 步：界面）")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .card(.subtle)
    }

    // MARK: - 小组件

    private func sectionTitle(_ text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private func privacyRow(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 设置项。enabled = false 表示还没接入，显示成灰的，
    /// 免得你或测试的朋友点了没反应，以为是 bug。
    private func settingRow(_ title: String, value: String, enabled: Bool,
                            showsChevron: Bool = false) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(enabled ? Theme.textPrimary : Theme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textTertiary)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())   // 让整行都能点，而不是只有字能点
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: 0.8)
    }
}

#Preview {
    ProfileView()
        .preferredColorScheme(.dark)
}
