import SwiftUI

/// 聊天里的一张图片。
///
/// 【为什么自己写而不是直接用 AsyncImage】
///
/// 直接用它有两个问题：
///   · 加载中没有占位，图片会从 0 尺寸"跳"出来，列表跟着抖
///   · 失败之后什么都不显示，用户只看到一块空白
///
/// 聊天里滚动很快，**尺寸稳定**比什么都重要 ——
/// 所以先用一个固定比例的灰块占住位置，图片到了再淡入。
struct ChatImageView: View {

    let url: URL

    /// 本地临时文件（还没上传完）和服务器上的图片走同一套，
    /// 只是本地的不需要占位等待。
    private var isLocal: Bool { url.isFileURL }

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.18))) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()

            case .failure:
                placeholder {
                    VStack(spacing: 5) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.system(size: 17))
                        Text("图片加载失败")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(Theme.textTertiary)
                }

            default:
                placeholder {
                    ProgressView().scaleEffect(0.7)
                }
            }
        }
        // 固定 4:3 的框，图片按需裁切。
        // 为什么不按图片真实比例：那样每张图高度都不一样，
        // 列表滚动时布局会一直重算，长列表上会明显掉帧。
        .frame(width: 200, height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func placeholder<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            Theme.surfaceAlt
            content()
        }
    }
}
