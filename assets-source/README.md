# 图标源文件

这个文件夹放的是**图标的原始素材和处理工具**，让图标以后可以重新生成，
而不是只剩一个"不知道怎么来的" PNG。

| 文件 | 是什么 |
|---|---|
| `icon-original.webp` | 原始素材（1203×1203，白底，无透明通道） |
| `imgtool.swift` | 处理工具：裁图 / 缩放 / 去白底 / 合成到纯色底 / 自动裁边 |

## 重新生成图标

```bash
# 1. 编译工具
xcrun swiftc -module-cache-path ./.tmp/mc assets-source/imgtool.swift -o ./.tmp/imgtool

# 2. 去白底（把白背景变透明，保留线条和那根绿草）
./.tmp/imgtool key assets-source/icon-original.webp ./.tmp/char.png 1.6

# 3. 自动裁到内容边界（原图留白不对称，不裁的话角色在图标里是歪的）
./.tmp/imgtool trim ./.tmp/char.png ./.tmp/char-trim.png 24

# 4. 合成成 App 图标
./.tmp/imgtool icon ./.tmp/char-trim.png ./.tmp/appicon.png 1024 12B7F5 82
#                                                                 ↑尺寸 ↑底色 ↑角色占比

# 5. 放进资源目录
cp ./.tmp/appicon.png "Huami Message/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
```

## 两个必须记住的坑

**① App 图标不能有透明通道。**
哪怕每个像素都是不透明的，只要 PNG 文件里带了 alpha 通道，上传就会被苹果拒。
所以 `imgtool` 的 `icon` 命令用的是**不带 alpha 的画布**（`noneSkipLast`）。
生成后一定要核对：

```bash
sips -g pixelWidth -g pixelHeight -g hasAlpha "Huami Message/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
# 期望：1024 / 1024 / hasAlpha: no
```

**② `sips` 的裁剪偏移语义不直观。**
我试过一次，结果和预期不符。裁剪是要精确到像素的操作，
所以这里用自己写的 `imgtool`，坐标以**左上角为原点**（和看图时的直觉一致）。

## 换个底色

主色蓝是 `#12B7F5`。想换成别的就改第 4 步最后那个参数：

```bash
./.tmp/imgtool icon ./.tmp/char-trim.png ./.tmp/appicon.png 1024 FFFFFF 82   # 白底
```
