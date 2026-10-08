import SwiftUI

/// 卡片的三种「重量」。
///
/// 浅色界面里，层次**不再靠模糊和发光**，而是靠三样东西：
///   1. 白和灰的对比（哪个是内容，哪个是底）
///   2. 一道极细极淡的描边（让白色卡片在浅灰底上"有边"）
///   3. 一点点阴影（只有真正"浮起来"的东西才给，比如输入栏）
///
/// 记住一句话：**阴影用得越省，界面越干净。**
/// 每个卡片都加阴影，看起来就像每个元素都在抢注意力 —— 那是廉价感的来源。
enum CardWeight {

    /// 白底 + 极细描边。最常用，列表项、信息卡都用它
    case plain

    /// 浅灰底，没有描边。用在"次级信息"上（比如引用原文）
    case subtle

    /// 白底 + 一点点阴影。只给真正浮在内容之上的东西（输入栏）
    case elevated
}

extension View {

    /// 给视图套一张卡片。
    ///
    /// 从「毛玻璃」换成「实色卡片」是这个版本最大的视觉变化，
    /// 而这个变化只发生在这一个函数里 —— 所有调用点一行都没改。
    /// 这就是把设计收进一个文件的好处。
    func card(_ weight: CardWeight = .plain, radius: CGFloat = Theme.cardRadius) -> some View {
        self
            .background {
                switch weight {
                case .plain:
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Theme.surface)
                case .subtle:
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Theme.surfaceAlt)
                case .elevated:
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Theme.surface)
                        // 阴影要"大而淡"。小而黑的阴影看起来像描边，很脏。
                        .shadow(color: .black.opacity(0.07), radius: 14, y: 4)
                }
            }
            .overlay {
                // 只有白底才需要描边 —— 浅灰底本身就在浅灰页面里，
                // 再描一圈就显得啰嗦了。
                if weight == .plain {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Theme.separator, lineWidth: 0.5)
                }
            }
    }
}

/// 一行极细的分隔线。
///
/// 单独抽出来，是因为"0.5 磅"这个数字如果散落在十个文件里，
/// 迟早会有人写成 1 磅，然后界面就不一致了。
struct HairLine: View {
    var inset: CGFloat = 0
    var body: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: 0.5)
            .padding(.leading, inset)
    }
}

/// 流式输出时那个一闪一闪的光标。
///
/// 它的作用不是好看，是**告诉用户「AI 还在想，别走」**。
/// 没有它，文字停顿的那零点几秒，用户会以为 App 卡住了 ——
/// 这正是「不丝滑」的来源。
struct StreamingCaret: View {

    @State private var visible = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Theme.accent)
            .frame(width: 2, height: 15)
            .opacity(visible ? 1 : 0.15)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}
