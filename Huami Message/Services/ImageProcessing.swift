import UIKit

/// 发之前的图片处理。
///
/// 【为什么一定要压】
///
/// 手机拍一张照片动辄 3-5MB，而聊天里看到的也就手机屏幕那么大。
/// 不压的话：上传慢、对方加载慢、你的存储和流量按 MB 计费地烧。
///
/// 压到 1600 长边 + 0.75 质量之后，一般在 200-400KB ——
/// **肉眼几乎看不出差别，体积小了十倍以上。**
extension UIImage {

    /// 聊天里发的图。
    func compressedForChat() -> Data? {
        resized(maxSide: 1600).jpegData(compressionQuality: 0.75)
    }

    /// 头像。尺寸更小 —— 它在界面上最大也就 88 磅（@3x 才 264 像素）。
    func compressedForAvatar() -> Data? {
        resized(maxSide: 512).jpegData(compressionQuality: 0.8)
    }

    /// 等比缩放到长边不超过 maxSide。已经够小就原样返回。
    ///
    /// 注意**不能放大** —— 一张 100×100 的图硬拉到 1600 只会变糊、还更占地方。
    private func resized(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide, longest > 0 else { return self }

        let scale = maxSide / longest
        let target = CGSize(width: (size.width * scale).rounded(),
                            height: (size.height * scale).rounded())

        let format = UIGraphicsImageRendererFormat.default()
        // 用 scale = 1：我们已经在按像素算了，再乘屏幕倍率就白压了
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
