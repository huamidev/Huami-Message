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

    var body: some View {
        NavigationStack {
            GlassPage {
                ScrollView {
                    VStack(spacing: 16) {
                        identityCard
                        privacyCard
                        settingsCard
                        aboutCard
                    }
                    .padding(16)
                    .padding(.bottom, 72)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("我")
        }
    }

    // MARK: - 身份

    private var identityCard: some View {
        HStack(spacing: 14) {
            Avatar(initial: "华", seed: 0, size: 60)

            VStack(alignment: .leading, spacing: 4) {
                Text("未登录")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                Text("第 1 步会接入账号（通过 Apple 登录）")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()
        }
        .padding(16)
        .glassCard(.thin)
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
                "结合上下文润色",
                "当前未开启。如果以后开启，会把最近几条消息发送给 AI 服务商，"
                + "并且每次都需要你明确确认 —— 不会默认开启。"
            )
            privacyRow(
                "聊天记录",
                "只存在你的手机和你自己的服务器账号里。"
            )
        }
        .padding(16)
        .glassCard(.thin)
    }

    // MARK: - 设置

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("设置", icon: "gearshape.fill", tint: Theme.accent)
                .padding(.bottom, 12)

            settingRow("AI 服务商", value: "DeepSeek", enabled: false)
            divider
            settingRow("删除账号", value: "待接入", enabled: false)
            divider
            settingRow("举报与屏蔽", value: "待接入", enabled: false)
        }
        .padding(16)
        .glassCard(.thin)
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("关于", icon: "info.circle.fill", tint: Color(red: 1.0, green: 0.78, blue: 0.35))

            Text("Huami Message")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))

            Text("这是一个「帮你把话说好」的工具，不是一个普通的聊天软件。")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)

            Text("版本 1.0 · 开发中（第 0 步：界面）")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(.ultraThin)
    }

    // MARK: - 小组件

    private func sectionTitle(_ text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private func privacyRow(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 设置项。enabled = false 表示还没接入，显示成灰的，
    /// 免得你或测试的朋友点了没反应，以为是 bug。
    private func settingRow(_ title: String, value: String, enabled: Bool) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(enabled ? 0.9 : 0.55))
            Spacer()
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(enabled ? 0.5 : 0.3))
        }
        .padding(.vertical, 11)
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .frame(height: 0.8)
    }
}

#Preview {
    ProfileView()
        .preferredColorScheme(.dark)
}
