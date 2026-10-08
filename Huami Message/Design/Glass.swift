import SwiftUI

/// 毛玻璃的三种「厚度」，对应苹果内置的三档材质。
///
/// 记一个直觉就够了：
/// - ultraThin 最透、最飘，但压不住花哨的背景，字容易看不清
/// - thin      日常最常用，透一点又有可读性
/// - regular   最不透明、字最好读，适合要长时间阅读或打字的地方
///
/// ⚠️ 千万不要用「半透明白色」去假装毛玻璃 —— 那样背后的东西完全透不过来，
///    看起来就是一块灰板子，立刻变廉价。必须用系统的 Material。
enum GlassThickness {
    case ultraThin, thin, regular

    var material: Material {
        switch self {
        case .ultraThin: .ultraThinMaterial
        case .thin:      .thinMaterial
        case .regular:   .regularMaterial
        }
    }
}

extension View {

    /// 给任意视图套一层毛玻璃卡片。
    ///
    /// 三个细节决定它是「高级」还是「廉价」：
    ///
    /// 1. 用系统材质（.ultraThinMaterial），它会真实地折射背后的内容；
    /// 2. 加一道 0.8 磅的白色描边 —— 模拟玻璃边缘的高光，这是「厚度感」的来源。
    ///    没有这道边，玻璃就是一块模糊的色块，扁的；
    /// 3. 用 continuous 连续圆角 —— iPhone 机身、iOS 图标用的都是它，
    ///    比普通圆角顺眼得多（普通圆角在转角处会有个生硬的折点）。
    func glassCard(
        _ thickness: GlassThickness = .ultraThin,
        radius: CGFloat = Theme.cardRadius,
        stroke: Double = 0.18
    ) -> some View {
        self
            .background(
                thickness.material,
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.white.opacity(stroke), lineWidth: 0.8)
            }
    }
}

/// 流式输出时那个一闪一闪的光标。
///
/// 它的作用不是好看，是**告诉用户「AI 还在想，别走」**。
/// 没有它，文字停顿的那零点几秒，用户会以为 App 卡住了 —— 这正是「不丝滑」的来源。
struct StreamingCaret: View {

    @State private var visible = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Theme.accent)
            .frame(width: 2.5, height: 16)
            .opacity(visible ? 1 : 0.12)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}
