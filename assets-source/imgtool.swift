// 小工具：裁图 / 缩放 / 合成到纯色底。
// 为什么要自己写：sips 的裁剪偏移语义不直观（我试过一次，结果和预期不符），
// 而裁剪是要精确到像素的操作，用不可靠的工具会反复返工。
//
// 用法：
//   imgtool crop    <in> <out> <x> <y> <w> <h>
//   imgtool scale   <in> <out> <size>
//   imgtool icon    <in> <out> <size> <bgHex> <scalePercent>
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let a = CommandLine.arguments
guard a.count >= 4 else { print("参数不足"); exit(1) }

func load(_ path: String) -> CGImage {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        print("读不到图片: \(path)"); exit(1)
    }
    return img
}

func write(_ img: CGImage, _ path: String) {
    guard let dest = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else { print("写不了: \(path)"); exit(1) }
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
}

func context(_ w: Int, _ h: Int) -> CGContext {
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        print("建不了画布"); exit(1)
    }
    return ctx
}

func color(_ hex: UInt32) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

/// 不带 alpha 通道的画布。
///
/// ⚠️ App 图标**必须**用这个。
/// 苹果明确要求上架图标不能含透明通道 —— 哪怕每个像素都是不透明的，
/// 只要 PNG 文件里带了 alpha 通道，上传时就会被拒。
/// 我第一版用了带 alpha 的画布，`sips -g hasAlpha` 立刻就报了出来。
func contextNoAlpha(_ w: Int, _ h: Int) -> CGContext {
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        print("建不了画布"); exit(1)
    }
    return ctx
}

switch a[1] {

case "crop":
    // x/y 以左上角为原点（和看图时的直觉一致），内部转成 CGContext 的左下原点
    guard a.count >= 8,
          let x = Int(a[4]), let y = Int(a[5]),
          let w = Int(a[6]), let h = Int(a[7]) else { print("crop 参数错"); exit(1) }
    let img = load(a[2])
    guard let cropped = img.cropping(to: CGRect(x: x, y: y, width: w, height: h)) else {
        print("裁剪失败"); exit(1)
    }
    write(cropped, a[3])
    print("crop \(img.width)x\(img.height) -> \(cropped.width)x\(cropped.height)")

case "scale":
    guard a.count >= 5, let size = Int(a[4]) else { print("scale 参数错"); exit(1) }
    let img = load(a[2])
    let ctx = context(size, size)
    // 高质量插值：缩小线稿时不用这个会糊成一团
    ctx.interpolationQuality = .high
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: size, height: size))
    write(ctx.makeImage()!, a[3])
    print("scale -> \(size)x\(size)")

case "icon":
    // 把角色合成到纯色底上，做成 App 图标。
    // 为什么需要它：原图是"白底 + 细黑线"，直接当 App 图标
    // 在桌面上看就是一块发白的方块，远看什么都没有。
    guard a.count >= 7, let size = Int(a[4]), let pct = Double(a[6]) else {
        print("icon 参数错"); exit(1)
    }
    let bg = UInt32(a[5], radix: 16) ?? 0x12B7F5
    let img = load(a[2])
    let ctx = contextNoAlpha(size, size)   // ← 关键：图标不能有 alpha 通道
    ctx.interpolationQuality = .high
    ctx.setFillColor(color(bg))
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    // 角色按比例居中放置
    let side = Double(size) * pct / 100
    let inset = (Double(size) - side) / 2

    ctx.draw(img, in: CGRect(x: inset, y: inset, width: side, height: side))
    write(ctx.makeImage()!, a[3])
    print("icon -> \(size)x\(size) 底色 #\(a[5]) 角色占比 \(pct)%")

case "key":
    // 把白色背景变透明，保留线条。
    //
    // 原理：一个像素越"暗"，就越可能是线条；越"白"，就越可能是背景。
    // 所以用 alpha = 1 - 最暗通道/255 来算透明度。
    // 这样抗锯齿产生的浅灰边缘会得到半透明，而不是一圈生硬的白边。
    //
    // 注意保留原始 RGB（不强制涂黑）—— 那样角色嘴里那根绿色的草才会还是绿的。
    let img = load(a[2])
    let w = img.width, h = img.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    guard let read = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                               bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        print("读像素失败"); exit(1)
    }
    read.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))

    let boost = a.count >= 5 ? (Double(a[4]) ?? 1.6) : 1.6
    for i in stride(from: 0, to: buf.count, by: 4) {
        let r = Double(buf[i]), g = Double(buf[i + 1]), b = Double(buf[i + 2])
        let darkest = min(r, min(g, b)) / 255
        // 曲线提一下对比，否则细线条会偏淡
        let alpha = min(1, (1 - darkest) * boost)
        if alpha <= 0.02 {
            buf[i] = 0; buf[i + 1] = 0; buf[i + 2] = 0; buf[i + 3] = 0
        } else {
            buf[i + 3] = UInt8(alpha * 255)
        }
    }
    guard let out = context(w, h).data else { print("失败"); exit(1) }
    // 把处理好的像素写回去
    guard let outCtx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                                 bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let result = outCtx.makeImage() else { print("生成失败"); exit(1) }
    _ = out
    write(result, a[3])
    print("key -> 白底已透明化 \(w)x\(h)")

case "softkey":
    // 把白底变透明 —— 但**用曲线压掉纸纹**，而不是线性放大。
    //
    // 【为什么要单独加一个命令，而不是改 key】
    //
    // 原来的 key 用的是  alpha = (1 - 最暗通道) * 增益，增益默认 1.6。
    // 原图是手绘的，纸面上有大量接近白的纹理噪点。
    // 乘 1.6 之后，这些噪点被提成了肉眼可见的灰斑 ——
    // 线条看起来毛毛的、断断续续的，像被啃过。
    //
    // 这里改成先算"离白色有多远"，再取幂：
    //     alpha = (1 - 最暗通道) ^ 指数
    // 只有**真正深**的像素才接近不透明，浅色的纸纹被压到接近 0。
    // 指数越大压得越干净（线条也会略细一点），默认 2。
    guard a.count >= 4 else { print("softkey 参数错"); exit(1) }
    let img = load(a[2])
    let w = img.width, h = img.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    guard let read = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                               bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        print("读像素失败"); exit(1)
    }
    read.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))

    let exponent = a.count >= 5 ? (Double(a[4]) ?? 1.6) : 1.6
    for i in stride(from: 0, to: buf.count, by: 4) {
        let darkest = Double(min(buf[i], min(buf[i + 1], buf[i + 2]))) / 255
        let alpha = pow(1 - darkest, exponent)
        if alpha <= 0.03 {
            buf[i] = 0; buf[i + 1] = 0; buf[i + 2] = 0; buf[i + 3] = 0
        } else {
            // ⚠️ **必须把 RGB 也乘上 alpha** —— 这就是之前线条发毛的真正原因。
            //
            // 这个画布用的是 premultipliedLast（预乘 alpha）格式。
            // 在这种格式里，存进去的 RGB 必须**已经乘过 alpha** ——
            // 也就是说 RGB 的值不能大于 alpha。
            //
            // 只设 alpha、不乘 RGB 的话，系统会按"已经乘过"去解释它：
            // 比如 alpha=0.5、RGB=128，会被当成"原始颜色 = 128/0.5 = 256"，
            // 直接溢出。表现出来就是线条变成一团花斑、边缘发毛。
            //
            // 我一开始以为是"增益把纸纹放大了"，换了曲线还是不行；
            // 真正的原因是这个。**看着像调参的问题，其实是编码格式用错了。**
            let a8 = UInt8(alpha * 255)
            buf[i] = UInt8(Double(buf[i]) * alpha)
            buf[i + 1] = UInt8(Double(buf[i + 1]) * alpha)
            buf[i + 2] = UInt8(Double(buf[i + 2]) * alpha)
            buf[i + 3] = a8
        }
    }
    guard let outCtx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                                 bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let result = outCtx.makeImage() else { print("生成失败"); exit(1) }
    write(result, a[3])
    print("softkey -> 已去白底（指数 \(exponent)，压制纸纹）")

case "trim":
    // 自动裁到"有内容的地方"，四周留一点边距。
    //
    // 为什么需要：原图的留白是不对称的（角色偏右、左边留了一大块给那根草）。
    // 直接拿去合成，角色在图标里就是歪的。Auto-trim 之后位置就自然居中了。
    guard a.count >= 4 else { print("trim 参数错"); exit(1) }
    let img = load(a[2])
    let w = img.width, h = img.height
    let pad = a.count >= 5 ? (Int(a[4]) ?? 8) : 8
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        print("读像素失败"); exit(1)
    }
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))

    // 【怎么判断"哪里是内容"】
    //
    // 优先看 alpha 通道（那是"去白底"之后的结果）。
    // 但如果整张图都是不透明的 —— 比如直接拿原图来裁 ——
    // 就看"这个像素离白色有多远"，那才是画上去的线条。
    //
    // 没有这个回退的话，直接裁原图会把整张图当成内容，等于没裁。
    var hasAlpha = false
    for i in stride(from: 3, to: buf.count, by: 4) where buf[i] < 250 {
        hasAlpha = true
        break
    }

    var minX = w, minY = h, maxX = 0, maxY = 0
    for y in 0..<h {
        for x in 0..<w {
            let i = (y * w + x) * 4
            let hit = hasAlpha
                ? buf[i + 3] > 12
                : (255 - min(buf[i], min(buf[i + 1], buf[i + 2]))) > 24
            if hit {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
    }
    guard maxX > minX, maxY > minY else { print("整张图都是空的"); exit(1) }

    let x0 = max(0, minX - pad), y0 = max(0, minY - pad)
    let x1 = min(w - 1, maxX + pad), y1 = min(h - 1, maxY + pad)
    // CGBitmapContext 内存第 0 行是图像顶部，所以直接用屏幕坐标即可
    guard let cropped = img.cropping(to: CGRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1)) else {
        print("裁剪失败"); exit(1)
    }
    write(cropped, a[3])
    print("trim \(w)x\(h) -> \(cropped.width)x\(cropped.height)")

default:
    print("未知命令 \(a[1])")
    exit(1)
}
