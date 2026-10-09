/// 头像。
///
/// 【为什么用「配色块 + 首字」而不是默认头像图片】
///
/// 新用户没上传头像时，一个灰色的默认头像等于没有信息 ——
/// 一屏十个都一样，认不出谁是谁。
/// 按 id 算一个稳定的颜色 + 名字首字，至少**同一个人每次都是同一个样子**，
/// 而且一眼能区分。iOS 版就是这么做的，两边看起来要一致。
const COLORS = [
  '#2f9bf5', '#10b981', '#f59e0b', '#ef4444', '#8b5cf6',
  '#ec4899', '#14b8a6', '#f97316', '#6366f1', '#84cc16',
]

export default function Avatar({
  name,
  seed,
  url,
  size = 48,
}: {
  name: string
  seed: number
  url?: string | null
  size?: number
}) {
  // 取模要防负数：某些算出来的 seed 可能是负的
  const color = COLORS[Math.abs(seed) % COLORS.length]
  const initial = (name || '?').trim().slice(0, 1).toUpperCase()

  return (
    <div
      className="avatar"
      style={{
        width: size,
        height: size,
        background: url ? undefined : color,
        fontSize: size * 0.42,
      }}
    >
      {url ? <img src={url} alt="" /> : initial}
    </div>
  )
}
