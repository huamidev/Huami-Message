import SwiftUI

/// 小助手贴在消息下面的判断。
///
/// 【样子是照着参考图改的】
///
/// 第一版我做成了一堆**带彩色进度条和百分比徽章的卡片** ——
/// 自己看着挺精致，但和用户要的效果不是一回事。
///
/// 参考图里是这样的：**一整块灰底、纯文字、每行一个「- 选项：百分比」**。
/// 像一条普通消息，而不是一个仪表盘。
///
/// 差别不只是好不好看：
///   · 进度条适合"比较两个数谁大"；但这里的百分比**不是一个可比的量**，
///     它只是模型给出的可能性。画成条会让人误以为它精确。
///   · 聊天界面里，**最不缺的就是视觉重量**。判断结果如果比消息本身还抢眼，
///     用户会先看判断、后看对方说了什么 —— 那就本末倒置了。
///
/// 所以：灰底、等宽数字、克制。它应该像旁边坐了个朋友小声说话，
/// 而不是弹出一块仪表盘。
struct DecisionCardsView: View {

    var status: String?
    var blocks: [DecisionBlock]
    var recommendation: String?
    var error: String?
    var sharedMessageCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            label

            if let error {
                bubble {
                    line(error, color: Theme.danger)
                }
            } else if blocks.isEmpty && recommendation == nil {
                bubble { line(status ?? "正在读这段对话…", color: Theme.textSecondary) }
            } else {
                bubble {
                    VStack(alignment: .leading, spacing: 11) {
                        ForEach(blocks) { block in
                            blockLines(block)
                        }
                        if let recommendation, !recommendation.isEmpty {
                            line("建议：" + recommendation, color: Theme.textPrimary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 名称行

    /// 参考图里这行是「Jev:」。我们用「小助手」+ 一句"读了最近几条" ——
    /// 后面那半句是有用的：用户能一眼看到**这次到底发出去了多少**。
    private var label: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkles")
                .font(.system(size: 9.5))
            Text("小助手")
                .font(.system(size: 11.5, weight: .medium))
            if sharedMessageCount > 0 {
                Text("· 读了最近 \(sharedMessageCount) 条")
                    .font(.system(size: 11))
            }
        }
        .foregroundStyle(Theme.accent)
        .padding(.leading, 3)
    }

    // MARK: - 灰底气泡

    private func bubble<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.surfaceAlt,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// 把 AI 返回的文字当成 Markdown 渲染。
    ///
    /// 【为什么需要这一步】
    ///
    /// 模型（DeepSeek 也是）习惯用 `**加粗**` 标重点。
    /// 直接当纯文字显示的话，用户会看到一堆星号 ——
    /// 上面那张验证截图里就是「**第一句里不要出现「因为」**」，
    /// 一眼就露馅，像是程序没做完。
    ///
    /// 用 `.inlineOnlyPreservingWhitespace`：只解释**行内**格式
    ///（加粗、斜体、行内代码），**保留换行** ——
    /// 判断结果本来就是多行的，如果让它按块级 Markdown 解析，
    /// 换行会被吃掉、缩进会乱。
    ///
    /// 解析失败就原样显示，不至于因为一个星号把整段吞掉。
    private func styled(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }

    private func line(_ text: String, color: Color) -> some View {
        Text(styled(text))
            .font(.system(size: 14))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 一个判断块

    @ViewBuilder
    private func blockLines(_ block: DecisionBlock) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // 小标题（参考图里那种「当前真实意图」），比正文略重一点
            if let title = block.title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }

            // 提问 / 判断的引子
            if !block.prompt.isEmpty, block.prompt != block.title {
                line(block.prompt, color: Theme.textPrimary)
            }

            // 选项：**就是一行「- 是：7%」**，不用进度条
            ForEach(block.options) { option in
                line("- \(option.label)：\(option.percent)%",
                     color: option.isRecommended ? Theme.textPrimary : Theme.textSecondary)
            }

            // 程度：参考图里是「危险等级：9 / 10」这样一行
            if let level = block.level {
                line("\(block.levelCaption ?? "程度")：\(level) / 10",
                     color: Theme.textPrimary)
            }
        }
    }
}
