import { useState } from 'react'
import { polish, POLISH_STYLES, type PolishStyle } from '../lib/ai'

/// 润色面板。
///
/// 【为什么是"选风格 → 看它写出来 → 一键用它"】
///
/// 用户想改一句话时，心里想的是"这样说不太合适"，而不是
/// "请帮我把这段话改得更得体一些"。所以：
///   · 不给他一个空白输入框让他描述需求（那是给 AI 工程师用的）
///   · 给三个说人话的选项，点一下就有结果
///   · 结果**流式**显示 —— 看着它写出来，比等一个转圈更有掌控感
///   · 最后一定是"用它"而不是"复制" —— 少一步操作
export default function PolishSheet({
  original,
  onUse,
  onClose,
}: {
  original: string
  onUse: (text: string) => void
  onClose: () => void
}) {
  const [style, setStyle] = useState<PolishStyle | null>(null)
  const [result, setResult] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  /// 每发起一次就加一，用来判断"回来的片段是不是这一次的"
  const [round, setRound] = useState(0)

  async function run(next: PolishStyle) {
    setStyle(next)
    setResult('')
    setError(null)
    setBusy(true)
    const myRound = round + 1
    setRound(myRound)

    try {
      await polish(original, next, (piece) => {
        // 只接受当前这一轮的片段 —— 用户连点几个风格时，
        // 上一次的余波不能混进来
        setResult((prev) => (myRound === round + 1 ? prev + piece : prev))
      })
    } catch (err) {
      setError(err instanceof Error ? err.message : '润色失败')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="sheet-backdrop" onClick={onClose}>
      <div className="sheet" onClick={(e) => e.stopPropagation()}>
        <h3>帮你把话说好</h3>
        <div className="quote">{original}</div>

        <div className="styles">
          {POLISH_STYLES.map((s) => (
            <button
              key={s.id}
              className={style === s.id ? 'style on' : 'style'}
              onClick={() => run(s.id)}
              disabled={busy}
            >
              <span className="style-title">{s.title}</span>
              <span className="style-hint">{s.hint}</span>
            </button>
          ))}
        </div>

        {error && <p className="msg error">{error}</p>}

        {(result || busy) && (
          <div className="result">
            {result}
            {busy && <span className="caret" />}
          </div>
        )}

        <div className="sheet-actions">
          <button className="btn ghost" onClick={onClose}>取消</button>
          <button
            className="btn primary"
            disabled={!result.trim() || busy}
            onClick={() => onUse(result.trim())}
          >
            用它
          </button>
        </div>
      </div>
    </div>
  )
}
