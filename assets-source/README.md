# 图标源文件

这个文件夹放的是**图标的原始素材和处理工具**，让图标以后可以重新生成，
而不是只剩一个"不知道怎么来的" PNG。

| 文件 | 是什么 |
|---|---|
| `icon-original.webp` | 原始素材（1203×1203，白底手绘线条） |
| `imgtool.swift` | 处理工具：裁图 / 缩放 / 去白底 / 正片叠底 / 合成 |

---

## ⚠️ 先读这一段：这个素材**不能抠图**

原图是**手绘的**，线条本身就带笔触纹理（深浅不均），纸面上还有大量接近白的噪点。

把"深浅"映射成透明度（也就是抠图）会**必然**毁掉它：

- 线条的笔触纹理 → 变成一段一段的斑点，看起来像被啃过
- 那根绿草 → 颜色浅，算出来 alpha 很低，几乎消失

我试过两种抠图（硬阈值、柔和曲线），**都不行**。

### 正确做法：正片叠底

```
结果 = 底色 × 原图 ÷ 255
```

- 白色(255) × 蓝色 = **蓝色** ← 背景自然"消失"
- 黑色(0) × 蓝色 = **黑色** ← 线条完整保留，抗锯齿也在

**没有任何"提取"动作，每一个像素都原样参与运算。** 这是给线稿换底色的标准做法。

代价：线条之外的颜色会被染上底色（绿草会偏青）。可以接受。

---

## 重新生成 App 图标

```bash
# 1. 编译工具
mkdir -p .tmp
xcrun swiftc -module-cache-path ./.tmp/mc assets-source/imgtool.swift -o ./.tmp/imgtool

# 2. 裁到内容边界（原图留白不对称，不裁的话角色是歪的）
#    注意：这里**不需要**先去白底 —— trim 在没有 alpha 通道时会用
#    "离白色多远"来找内容边界
./.tmp/imgtool trim assets-source/icon-original.webp ./.tmp/trim.png 24

# 3. 正片叠底合成 App 图标
./.tmp/imgtool icon ./.tmp/trim.png ./.tmp/appicon.png 1024 12B7F5 82 multiply
#                                                                 ↑尺寸 ↑底色 ↑占比 ↑关键

# 4. 放进资源目录
cp ./.tmp/appicon.png "Huami Message/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
```

### 必须核对

```bash
sips -g pixelWidth -g pixelHeight -g hasAlpha \
  "Huami Message/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
# 期望：1024 / 1024 / hasAlpha: no
```

**App 图标绝对不能有透明通道**，哪怕每个像素都不透明也不行 ——
PNG 文件里带 alpha 通道，上传 App Store 就会被拒。
`imgtool` 的 `icon` 命令用的是不带 alpha 的画布（`noneSkipLast`），所以没问题。

---

## 重新生成 App 里的小助手头像

头像要**真透明**（它显示在 App 的浅色渐变背景上），所以这里必须抠图。
但用修好之后的 `softkey`：

```bash
./.tmp/imgtool softkey assets-source/icon-original.webp ./.tmp/av.png 1.6
./.tmp/imgtool trim    ./.tmp/av.png ./.tmp/av-trim.png 10

D="Huami Message/Assets.xcassets/AssistantAvatar.imageset"
./.tmp/imgtool scale ./.tmp/av-trim.png "$D/avatar@3x.png" 192
./.tmp/imgtool scale ./.tmp/av-trim.png "$D/avatar@2x.png" 128
./.tmp/imgtool scale ./.tmp/av-trim.png "$D/avatar.png"     64
```

> 头像上还能看到一点手绘纸纹 —— 那是**素材本身**的一部分，
> 在 64 磅的实际显示尺寸下看不出来。

---

## imgtool 命令速查

| 命令 | 作用 |
|---|---|
| `trim <in> <out> [边距]` | 裁到内容边界。有 alpha 用 alpha，没有就用"离白色多远" |
| `key <in> <out> [增益]` | 去白底（**别用**，见上） |
| `softkey <in> <out> [指数]` | 去白底（曲线，已修好预乘 alpha） |
| `icon <in> <out> <尺寸> <底色> <占比> [multiply]` | 合成 App 图标 |
| `scale <in> <out> <尺寸>` | 缩放 |

---

## 三个必须记住的坑

**① App 图标不能有透明通道**（见上）。

**② 预乘 alpha 的画布里，RGB 必须一起乘。**

这一条害我调了很久。`CGBitmapContext` 用的是 `premultipliedLast` 格式，
在这种格式里**存进去的 RGB 必须已经乘过 alpha**（RGB 不能大于 alpha）。

只设 alpha、不乘 RGB 的话，系统会按"已经乘过"去解释：
`alpha=0.5, RGB=128` 会被算成原始颜色 `128 / 0.5 = 256`，直接溢出。
表现出来就是**线条变成一团花斑、边缘发毛**。

我一开始以为是"增益把纸纹放大了"，换了曲线还是不行 ——
真正的原因是编码格式用错了。

> **看着像"调参"的问题，有时候其实是"格式"的问题。**
> 遇到渲染结果不对，先检查色彩空间和 alpha 格式，再去调参数。

**③ `sips` 的裁剪偏移语义不直观。**
我试过一次，结果和预期不符。裁剪是要精确到像素的操作，
所以这里用自己写的 `imgtool`，坐标以**左上角为原点**（和看图时的直觉一致）。

---

## 换个底色

主色蓝是 `#12B7F5`。想换成别的就改第 3 步那个参数：

```bash
./.tmp/imgtool icon ./.tmp/trim.png ./.tmp/appicon.png 1024 FFFFFF 82 multiply   # 白底
```

> ⚠️ **换底色之后一定要在桌面上看一眼**（不是看生成出来的 PNG）。
> iOS 会缓存图标，重新安装后可能还显示旧的，
> 隔几秒再截一次图，或者删除重装。
