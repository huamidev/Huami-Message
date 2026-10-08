import SwiftUI

/// 页面背景。
///
/// 之前这里是会缓慢流动的"极光"（深色 + 三个彩色光斑 + 毛玻璃）。
/// 现在换成浅色的、几乎看不出变化的一层灰 —— 这是 TIM 那种风格的底色。
///
/// ⚠️ 注意：**极光那套代码不是被删掉了，是换掉了。**
/// 它还在 git 历史里（commit 2edd74c）。哪天你想要"炫"一点的主题，
/// 把 AuroraBackground 找回来，再把 Theme 的颜色换回去就行 ——
/// 因为所有颜色都只在 Theme.swift 里定义，界面代码一行都不用动。
///
/// 留着一点极淡的纵向渐变（而不是纯色），是因为纯色大面积铺开会显得"死"。
/// 从 #F5F6F8 到 #EFF0F2，浅到你几乎看不出，但眼睛会觉得舒服。
struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Theme.background, Color(hex: 0xEBECEF)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
