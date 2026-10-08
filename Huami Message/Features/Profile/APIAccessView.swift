import SwiftUI

/// 「API 接入」——让用户用自己的 AI。
///
/// 【为什么要有这一页】
///
/// 默认用的是搭这个 App 的人配在服务器上的密钥。那意味着
/// **所有朋友的 AI 花费都压在一个人头上**，人一多就撑不住。
///
/// 所以留一个口子：谁想用自己的 DeepSeek 账号，就填自己的密钥，
/// 花自己的钱。不想折腾的人什么都不用做，照常能用 —— 这是关键，
/// **不能因为要"支持自带密钥"就把默认路径变得麻烦。**
struct APIAccessView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var input = ""
    @State private var saved = false
    @State private var saveFailed = false

    private var hasPersonalKey: Bool { PersonalAIKey.isSet }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    currentCard
                    inputCard
                    howToCard
                }
                .padding(16)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(AppBackground())
            .navigationTitle("API 接入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .font(.system(size: 16, weight: .medium))
                }
            }
        }
    }

    // MARK: - 现在用的是哪个

    private var currentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("现在用的是", systemImage: "antenna.radiowaves.left.and.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)

            HStack(spacing: 9) {
                Image(systemName: hasPersonalKey ? "person.fill.checkmark" : "gift.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(hasPersonalKey ? Theme.accent : Theme.mint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(hasPersonalKey ? "你自己的密钥" : "我们提供的")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text(hasPersonalKey
                         ? (PersonalAIKey.masked ?? "")
                         : "不用做任何事，直接能用")
                        .font(.system(size: 12, design: hasPersonalKey ? .monospaced : .default))
                        .foregroundStyle(Theme.textTertiary)
                }

                Spacer(minLength: 0)
            }

            if hasPersonalKey {
                Button {
                    Haptics.warning()
                    PersonalAIKey.clear()
                    input = ""
                    withAnimation(.snappy) { saved = true }
                } label: {
                    Text("改回用默认的")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.danger)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .card()
    }

    // MARK: - 填密钥

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("填自己的 DeepSeek 密钥")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)

            TextField("sk-...", text: $input)
                .font(.system(size: 14, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(Theme.surfaceAlt,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            if saved {
                Text(saveFailed
                     ? "没能保存（这台设备上的钥匙串不可用，真机上正常）"
                     : "已保存 ✓ 之后的 AI 调用会用它，花的是你自己的额度")
                    .font(.system(size: 12))
                    .foregroundStyle(saveFailed ? Theme.danger : Theme.mint)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Haptics.tap()
                let ok = PersonalAIKey.save(input)
                saveFailed = !ok
                saved = true
                if ok { input = "" }
            } label: {
                Text("保存")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        PersonalAIKey.looksValid(input) ? Theme.accent : Theme.textTertiary,
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!PersonalAIKey.looksValid(input))

            Text("密钥只存在你手机的钥匙串里，只在你用 AI 的时候发给服务器，**不会存下来**。")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .card()
    }

    // MARK: - 怎么拿密钥

    private var howToCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("怎么拿到密钥")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)

            step(1, "打开 DeepSeek 开放平台，注册一个账号")
            step(2, "左边「充值」里充一点钱（这个平台是按用量扣费的）")
            step(3, "左边「API Keys」→ 创建一个 → 复制那串 sk- 开头的")

            Link(destination: URL(string: "https://platform.deepseek.com/api_keys")!) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 13))
                    Text("打开 DeepSeek 开放平台")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.accentSoft,
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }

            Text("不用自己的也行 —— 那就是用我们提供的，你什么都不用管。")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .card()
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text("\(number)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 17, height: 17)
                .background(Theme.accent, in: Circle())

            Text(text)
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}
