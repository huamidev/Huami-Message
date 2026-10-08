import SwiftUI

/// 首次启动的同意页。
///
/// 【为什么必须有这一页】
///
/// App Store 审核指南 1.2 条要求：带用户生成内容（也就是能互发消息）的 App，
/// 必须有一份**写明零容忍条款**的用户协议，并且用户要明确同意。
/// 没有它，审核会被拒。
///
/// 【设计上的取舍：不指望有人读完】
///
/// 没人会读完一份隐私政策。所以这一页只给**最关键的四条**，
/// 完整内容放在点一下就能看到的地方。
///
/// 这不是"藏起来"，而是把关键信息主动递到眼前 ——
/// 把四十段法律文本糊在首屏，用户只会闭着眼点"同意"，那才是真正的不知情。
struct TermsGateView: View {

    /// 用户点了「同意并继续」
    var onAccept: () -> Void

    @State private var showDocument: LegalDocument?
    @State private var showDeclineNotice = false

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 22) {
                    header
                    keyPoints
                    documentLinks
                    buttons
                }
                .padding(22)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(item: $showDocument) { document in
            LegalDocumentView(document: document)
        }
        .alert("需要同意后才能使用", isPresented: $showDeclineNotice) {
            Button("再看看") {}
            Button("查看服务条款") { showDocument = .terms }
        } message: {
            Text("这个 App 需要你与好友互发消息，所以必须先同意服务条款（其中包含对骚扰、色情、暴力等内容的零容忍条款）。如果你不同意，我们没办法让你使用它 —— 但你可以随时点上面的链接把条款读完再决定。")
        }
    }

    // MARK: - 顶部

    private var header: some View {
        VStack(spacing: 12) {
            MascotAvatar(size: 72)

            Text("欢迎使用 Huami Message")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Text("一个帮你把话说好的聊天工具")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, 12)
    }

    // MARK: - 四条要点

    private var keyPoints: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(LegalDocument.keyPoints.enumerated()), id: \.offset) { _, point in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: point.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 26, height: 26)
                        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(point.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(point.detail)
                            .font(.system(size: 12.5))
                            .lineSpacing(3)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(16)
        .card()
    }

    // MARK: - 完整文档入口

    private var documentLinks: some View {
        HStack(spacing: 10) {
            ForEach(LegalDocument.allCases) { document in
                Button {
                    Haptics.tap()
                    showDocument = document
                } label: {
                    HStack(spacing: 5) {
                        Text(document.title)
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Theme.surface, in: Capsule())
                    .overlay { Capsule().strokeBorder(Theme.separator, lineWidth: 0.5) }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 按钮

    private var buttons: some View {
        VStack(spacing: 10) {
            Button {
                Haptics.success()
                onAccept()
            } label: {
                Text("同意并继续")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.myBubbleGradient, in: Capsule())
            }
            .buttonStyle(.plain)

            Button {
                showDeclineNotice = true
            } label: {
                Text("不同意")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
    }
}
