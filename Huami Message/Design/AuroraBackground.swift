import SwiftUI

/// 会缓慢流动的极光背景。
///
/// 这是整个毛玻璃效果的「地基」，请务必理解它，因为它是你要求的
/// 「Apple Music 那种质感」的根本原理：
///
/// 毛玻璃的本质是「半透明 + 把背后的东西模糊掉」。
/// 所以如果背后只是一块纯色，模糊完还是纯色 —— 完全看不出玻璃感，只会显得灰扑扑。
/// 只有背后有**缓慢移动的彩色光斑**，「透过玻璃看到东西在动」的层次才出得来。
/// Apple Music 的播放页就是这个原理：背后是专辑封面的颜色在缓慢流动。
///
/// 所以先有会动的背景，毛玻璃才有意义。这就是为什么它是第 0 步，而不是最后一步。
struct AuroraBackground: View {

    /// 0 → 1 的动画进度。它一变，所有光斑的位置就跟着变。
    @State private var drift: CGFloat = 0

    var body: some View {
        // ⚠️ 这里有个坑，我真的踩了，而且是用截图验证发现的，务必记住：
        //
        // 我一开始写成  ZStack { 底色; 光斑… }。
        // 但光斑是 520×520 的**固定尺寸**，而 ZStack 的尺寸取「所有子视图里最大的那个」。
        // 于是整个背景被撑成 520 宽 —— 比 iPhone 的 402 还宽。
        // 外层 RootView 的 ZStack 跟着被撑宽，导致：
        //   · 导航栏标题和会话卡片被一起撑宽、被屏幕左右裁掉；
        //   · 背景只有中间 520 高是亮的，屏幕上下是死黑。
        //
        // 教训：**装饰性的东西绝对不能参与布局计算。**
        // 用 overlay 把光斑「挂」在底色上 —— overlay 不参与父视图的尺寸计算，
        // 所以光斑再大也撑不坏背景。决定背景尺寸的只有那个可伸缩的渐变。
        LinearGradient(
            colors: [
                Color(red: 0.060, green: 0.070, blue: 0.130),
                Color(red: 0.020, green: 0.025, blue: 0.050),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay { glows }
        // 底部压暗。
        // 两个作用：① 底下的 tab bar 那块有「沉下去」的感觉，不会浮；
        //           ② 最下面那团青色不要那么抢眼 —— 光斑全屏均匀铺开会显得廉价，
        //              有一处暗下去，整个画面才有重心。
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, Color(red: 0.015, green: 0.020, blue: 0.040).opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 300)
        }
        .ignoresSafeArea()
        .onAppear {
            // 18 秒走一个来回。慢到你几乎察觉不到它在动，
            // 但如果真把它停住，整个界面立刻会觉得「死板」。
            withAnimation(.easeInOut(duration: 18).repeatForever(autoreverses: true)) {
                drift = 1
            }
        }
    }

    /// 三团光斑。大小、位置、颜色、强度都不同，叠在一起才自然。
    /// 强度是调出来的：底部那团青色如果和上面一样强，整个下半屏会被冲成一片青绿，
    /// 看着很「平」。让它弱一点，画面才有主次。
    private var glows: some View {
        ZStack {
            glow(Theme.accent,
                 size: 520,
                 intensity: 0.55,
                 at: CGPoint(x: -110, y: -160),
                 move: CGSize(width: 90, height: 60))

            glow(Theme.accentDeep,
                 size: 460,
                 intensity: 0.50,
                 at: CGPoint(x: 150, y: 60),
                 move: CGSize(width: -70, height: 90))

            glow(Theme.mint,
                 size: 400,
                 intensity: 0.28,
                 at: CGPoint(x: -60, y: 300),
                 move: CGSize(width: 100, height: -80))
        }
        // 让这一层只占据屏幕大小。光斑溢出到屏幕外的部分反正也看不见。
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 一团柔光。
    ///
    /// 这里用「径向渐变」而不是「模糊圆形」，是性能上的讲究：
    /// 模糊（blur）要真的逐像素去算，三团大模糊会明显掉帧、发烫、耗电；
    /// 径向渐变是画的时候自带的柔和过渡，几乎不花性能。
    /// 视觉效果几乎一样，代价差好几倍 —— 这种取舍是做「丝滑」的关键。
    private func glow(_ color: Color,
                      size: CGFloat,
                      intensity: Double,
                      at point: CGPoint,
                      move: CGSize) -> some View {
        RadialGradient(
            colors: [color.opacity(intensity), color.opacity(0)],
            center: .center,
            startRadius: 0,
            endRadius: size / 2
        )
        .frame(width: size, height: size)
        .offset(x: point.x + move.width * drift, y: point.y + move.height * drift)
        // plusLighter：光斑重叠的地方会「发亮」而不是互相盖住，更像真的光
        .blendMode(.plusLighter)
    }
}

#Preview {
    AuroraBackground()
}
