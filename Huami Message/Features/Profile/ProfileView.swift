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
        HStack(spacing: 14) {
            Avatar(initial: displayInitial, seed: auth.account?.avatarSeed ?? 0, size: 60)

            VStack(alignment: .leading, spacing: 5) {
                Text(auth.account?.displayName ?? "未登录")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text(auth.account?.email ?? "还没有登录")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)

                // 邀请码先摆出来。加好友的功能接上服务器就能用，
                // 但"我的邀请码是什么"这件事现在就该让用户看得到。
                if let code = auth.account?.inviteCode {
                    HStack(spacing: 5) {
                        Image(systemName: "ticket.fill")
                            .font(.system(size: 10))
                        Text("邀请码 \(code)")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.accentSoft, in: Capsule())
                }
            }

            Spacer()
        }
        .padding(16)
        .card()
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
                "只有你主动点开小助手、并再点一次「帮我看看怎么回」时，"
                + "才会把最近 10 条消息发给 AI 服务商。"
                + "发送前会把你将要发出的内容原样显示出来，你不点就不会发送。"
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
                Haptics.tap()
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
