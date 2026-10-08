import SwiftUI

/// 所有一级页面的统一外壳：底下铺极光，上面放内容。
///
/// ⚠️ 为什么背景必须放在页面**里面**，而不是放在 RootView 的 TabView 后面？
///
/// 因为 TabView、NavigationStack 这些系统容器会给自己画一层**不透明背景**。
/// 深色模式下那层背景正好是纯黑 —— 放在它们后面的东西会被整个盖住，一点都看不见。
///
/// 我第一版就是把 AuroraBackground 放在 RootView 的 ZStack 里、TabView 后面，
/// 结果背景一片死黑。这不是看出来的，是写了个小工具**取像素值**量出来的：
/// 该是 #0F1221 的地方量出来是 #000000。挪到页面内部之后立刻就对了。
///
/// 记住这条经验：**往系统容器「后面」塞东西通常无效，要往「里面」塞。**
struct GlassPage<Content: View>: View {

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            AuroraBackground()
            content
        }
    }
}
