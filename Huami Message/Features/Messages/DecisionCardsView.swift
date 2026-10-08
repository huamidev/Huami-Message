import SwiftUI

/// 小助手的判断，**直接渲染在聊天记录里**。
///
/// 【为什么不做成弹窗，而是插在对话中间】
///
/// 因为这个判断是"针对上面那段对话"的。
/// 放在弹窗里，用户得记住刚才说了什么；插在对话下面，它就在该在的位置上，
/// 而且滑上去看一眼原文再滑下来，永远是同一屏之内的事。
///
/// 【为什么每个选项都有一条长度不同的底色】
///
/// 数字（72%）要读，长度不用读 —— 一眼就分出主次。
/// 人在不知道该怎么回消息的那一刻是慌的，能少读一个字就少读一个字。
struct DecisionCardsView: View {

    /// 状态提示（还在思考时显示）
    let status: String?

    /// 一个一个小方块
    let blocks: [DecisionBlock]

    /// 最后的建议动作
    let recommendation: String?

    /// 这次把多少条消息发给了 AI（如实告知，是隐私承诺的一部分）
    let sharedMessageCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            label

            if blocks.isEmpty {
                thinkingCard
            } else {
                ForEach(blocks) { block in
                    blockView(block)
                        // 方块一个一个冒出来 —— 这个动画让"它在想"这件事看得见
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.94, anchor: .top).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
            }

            if let recommendation {
                recommendationCard(recommendation)
                    .transition(.scale(scale: 0.94, anchor: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.3), value: blocks.count)
        .animation(.snappy(duration: 0.3), value: recommendation)
    }

    // MARK: - 顶部标识

    private var label: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkles")
                .font(.system(size: 9, weight: .semibold))
            Text("小助手")
                .font(.system(size: 10.5, weight: .semibold))
            if sharedMessageCount > 0 {
                Text("· 读了最近 \(sharedMessageCount) 条")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .foregroundStyle(Theme.accent)
        .padding(.leading, 4)
    }

    // MARK: - 还在想

    private var thinkingCard: some View {
        HStack(spacing: 8) {
            StreamingCaret()
            Text(status ?? "正在读这段对话")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Theme.surfaceAlt,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - 一个方块

    @ViewBuilder
    private func blockView(_ block: DecisionBlock) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            if let title = block.title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }

            Text(block.prompt)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            switch block.kind {
            case .options:
                VStack(spacing: 5) {
                    ForEach(block.options) { option in
                        optionRow(option)
                    }
                }
            case .level:
                levelRow(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surfaceAlt,
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Theme.separator, lineWidth: 0.5)
        )
    }

    // MARK: - 一个选项（带长度底色）

    private func optionRow(_ option: DecisionOption) -> some View {
        HStack(spacing: 8) {
            Text(option.label)
                .font(.system(size: 12.5, weight: option.isStrong ? .semibold : .regular))
                .foregroundStyle(option.isStrong ? Theme.textPrimary : Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 6)

            Text("\(option.percent)%")
                .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(option.isStrong ? Theme.accent : Theme.textTertiary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(alignment: .leading) {
            // 用 scaleEffect 画长度条，而不是 GeometryReader ——
            // 这里只需要"按比例缩放"，不需要知道具体宽度，用不上那么重的工具。
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(option.isStrong
                      ? Theme.accent.opacity(0.14)
                      : Theme.textTertiary.opacity(0.10))
                .scaleEffect(x: max(0.03, CGFloat(option.percent) / 100), anchor: .leading)
        }
    }

    // MARK: - 量级（危险等级那种）

    private func levelRow(_ block: DecisionBlock) -> some View {
        let level = block.level ?? 0
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(level)")
                    .font(.system(size: 26, weight: .bold).monospacedDigit())
                    .foregroundStyle(levelColor(level))
                Text("/ 10")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                Spacer(minLength: 0)
                if let caption = block.levelCaption {
                    Text(caption)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            // 十格刻度。人慌的时候需要一个刻度，"6 分"比"有点严重"有用。
            HStack(spacing: 3) {
                ForEach(1...10, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(i <= level ? levelColor(level) : Theme.separator)
                        .frame(height: 5)
                }
            }
        }
    }

    /// 量级的颜色：低绿、中黄、高红。
    /// 颜色比数字先被看见，所以这一层是有实际作用的，不只是装饰。
    private func levelColor(_ level: Int) -> Color {
        switch level {
        case ..<4:  Theme.mint
        case 4..<8: Theme.warning
        default:    Theme.danger
        }
    }

    // MARK: - 最后那条建议

    private func recommendationCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text("建议动作")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text(LocalizedStringKey(text))
                    .font(.system(size: 13.5))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.accentSoft,
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}
