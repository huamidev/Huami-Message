import SwiftUI

/// 小助手的形象。
///
/// 【为什么做成"圆角方块"，而不是抠成透明的图案】
///
/// 素材是手绘的，线条本身带笔触纹理、纸面有接近白的噪点。
/// 把它抠成透明的话线条会发毛、变斑点 —— 我试过硬阈值和柔和曲线，都不行
///（原因和验证过程见 `assets-source/README.md`）。
///
/// 所以干脆**用它本身**：和 App 图标是**同一张图、同一种处理**（原图直接用），
/// 显示的时候裁成圆角方块。看起来就像一个小图标，而不是一张贴歪的透明贴纸。
///
/// 顺带的好处：和桌面上的 App 图标长得一样，用户会觉得"这是同一个东西"。
struct MascotAvatar: View {

    var size: CGFloat = 64

    /// 圆角比例。
    /// 0.23 是照着 iOS 图标那种"方中带圆"的感觉定的 ——
    /// 太小像证件照，太大像药丸。
    private var cornerRadius: CGFloat { size * 0.23 }

    var body: some View {
        Image("AssistantAvatar")
            .resizable()
            // 用 fill 而不是 fit：图片是方的、显示区域也是方的，
            // 但 fill 能保证**不留白边**（哪怕以后换成非方形素材也不会变形拉丝）
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.separator, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.07), radius: 6, y: 2)
    }
}
