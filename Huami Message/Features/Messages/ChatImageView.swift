import SwiftUI

/// 聊天里的一张图片。
///
/// 【为什么不用 AsyncImage】
///
/// 因为它**不告诉你图片的尺寸**。而聊天里最重要的一件事是
/// **先占好位置再加载** —— 否则图片会从 0 尺寸"跳"出来，列表跟着抖，
/// 用户正在看的那条消息会被推走。
///
/// 更糟的是我第一版为了避开这个问题，**用了固定 4:3 的框** ——
/// 位置是稳了，但**画面被裁掉了**：竖着拍的照片上下各切一块，
/// 截图左右各切一块。用户发出去的东西和对方看到的不一样，这是不能接受的。
///
/// 所以现在：自己加载、自己量尺寸，**按真实比例显示，一点都不裁**。
/// 尺寸量出来之后缓存起来，往上翻历史时不会再跳。
struct ChatImageView: View {

    let url: URL

    @State private var image: UIImage?

    /// 显示尺寸。规则见 `displaySize`。
    private var ratio: CGFloat {
        if let image, image.size.height > 0 {
            return image.size.width / image.size.height
        }
        return ImageRatioCache.shared.ratio(for: url) ?? 1.0
    }

    /// 按比例算出一个"该占多大"的框。
    ///
    /// 两边都限了范围：
    ///   · 上限 —— 一张全景图不能横到把屏幕撑破
    ///   · 下限 —— 一张细长的截图不能窄成一条缝
    ///
    /// 极端比例会留一点底色（用 scaledToFit 不裁切），
    /// 这是刻意的取舍：**宁可留白，不可裁掉用户拍的东西。**
    private var displaySize: CGSize {
        let maxWidth: CGFloat = 220
        let maxHeight: CGFloat = 280
        let ratio = min(max(self.ratio, 0.55), 1.9)

        if ratio >= 1 {
            return CGSize(width: maxWidth, height: (maxWidth / ratio).rounded())
        }
        return CGSize(width: (maxHeight * ratio).rounded(), height: maxHeight)
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ZStack {
                    Theme.surfaceAlt
                    ProgressView().scaleEffect(0.7)
                }
            }
        }
        .frame(width: displaySize.width, height: displaySize.height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .task(id: url) {
            // 本地临时文件同步就能读，不用走网络
            if let cached = ImageRatioCache.shared.image(for: url) {
                image = cached
                return
            }
            if let loaded = await ImageRatioCache.shared.load(url) {
                withAnimation(.easeOut(duration: 0.16)) { image = loaded }
            }
        }
    }
}

/// 图片和尺寸的内存缓存。
///
/// 【为什么必须缓存尺寸，而不只是缓存图】
///
/// 因为**尺寸决定布局**。不缓存的话，每次滚动回来都要重新等加载、
/// 重新把这一条从默认比例"撑"成真实比例 —— 一屏里十条图片消息就是十次抖动。
///
/// 只用内存，不落磁盘：聊天记录滚出屏幕之后本来就会释放，
/// 落盘还要处理失效和清理，不值得。
@MainActor
final class ImageRatioCache {

    static let shared = ImageRatioCache()

    private var images: [URL: UIImage] = [:]
    private var ratios: [URL: CGFloat] = [:]

    private init() {}

    func image(for url: URL) -> UIImage? { images[url] }

    func ratio(for url: URL) -> CGFloat? { ratios[url] }

    func load(_ url: URL) async -> UIImage? {
        if let cached = images[url] { return cached }

        do {
            let data: Data
            if url.isFileURL {
                data = try Data(contentsOf: url)
            } else {
                let (loaded, _) = try await URLSession.shared.data(from: url)
                data = loaded
            }
            guard let image = UIImage(data: data) else { return nil }
            store(image, for: url)
            return image
        } catch {
            return nil
        }
    }

    private func store(_ image: UIImage, for url: URL) {
        images[url] = image
        if image.size.height > 0 {
            ratios[url] = image.size.width / image.size.height
        }
    }
}
