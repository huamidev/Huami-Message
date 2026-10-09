import { useState } from 'react'
import {
  advise, ASSISTANT_INTENTS, type AssistantIntent, type DecisionBlock,
} from '../lib/ai'
import type { Message } from '../lib/types'

/// 小助手：看一段对话，给判断和建议。
///
/// 【为什么它返回的不是一段文字，而是几个"方块"】
///
/// "他什么意思"这种问题，一句"他大概是想确认你有没有把事放心上"
/// 听起来像算命 —— 说得斩钉截铁，但没有任何分寸。
///
/// 换成**几个选项 + 概率**，反而更接近人真实的判断方式：
/// 你的直觉本来就是"八成是这个，但也许只是随口一说"。
/// 把这种不确定摆出来，比假装确定更诚实，也更有用。
///
/// 下面那一句"建议"才是可以直接照做的。
export default function AssistantSheet({
  messages,
  friendName,
  onClose,
}: {
  messages: Message[]
  friendName: string
  onClose: () => void
}) {
  const [intent, setIntent] = useState<AssistantIntent | null>(null)
  const [status, setStatus] = useState('')
  const [blocks, setBlocks] = useState<DecisionBlock[]>([])
  const [advice, setAdvice] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function run(next: AssistantIntent) {
    setIntent(next)
    setStatus('')
    setBlocks([])
    setAdvice('')
    setError(null)
    setBusy(true)

    // 只发最近 20 条 —— 这是对用户的隐私承诺，不能只是说说
    const recent = messages.slice(-20).map((m) => ({
      mine: !!m.mine,
      text: m.body || (m.image_url ? '[图片]' : '[语音]'),
    }))

    try {
      await advise({
        friendName,
        intent: next,
        messages: recent,
        onEvent: (event) => {
          if (event.type === 'status') setStatus(event.value)
          else if (event.type === 'block') setBlocks((prev) => [...prev, event.value])
          else if (event.type === 'recommendation') setAdvice(event.value)
        },
      })
    } catch (err) {
      setError(err instanceof Error ? err.message : '分析失败')
    } finally {
      setBusy(false)
      setStatus('')
    }
  }

  return (
    <div className="sheet-backdrop" onClick={onClose}>
      <div className="sheet" onClick={(e) => e.stopPropagation()}>
        <h3>小助手</h3>
        <p className="muted small">
          会把你和 {friendName} 最近 20 条消息发给 AI 服务商
        </p>

        <div className="styles">
          {ASSISTANT_INTENTS.map((i) => (
            <button
              key={i.id}
              className={intent === i.id ? 'style on' : 'style'}
              onClick={() => run(i.id)}
              disabled={busy}
            >
              <span className="style-title">{i.title}</span>
            </button>
          ))}
        </div>

        {busy && status && <p className="muted small">{status}…</p>}
        {error && <p className="msg error">{error}</p>}

        {blocks.map((b, index) => (
          <div className="block" key={index}>
            {b.title && <div className="block-title">{b.title}</div>}
            <div className="block-prompt">{b.prompt}</div>

            {b.kind === 'options' && b.options && (
              <div className="options">
                {b.options.map((o, i) => (
                  <div className={o.isRecommended ? 'option on' : 'option'} key={i}>
                    <div className="option-line">
                      <span className="option-label">{o.label}</span>
                      <span className="option-percent">{o.percent}%</span>
                    </div>
                    {/* 用条而不是只写数字：一眼能看出比例关系 */}
                    <div className="bar">
                      <div className="bar-fill" style={{ width: `${o.percent}%` }} />
                    </div>
                  </div>
                ))}
              </div>
            )}

            {b.kind === 'level' && typeof b.level === 'number' && (
              <div className="level">
                <div className="level-num">{b.level}<span>/10</span></div>
                <div className="bar">
                  <div className="bar-fill" style={{ width: `${b.level * 10}%` }} />
                </div>
              </div>
            )}
          </div>
        ))}

        {advice && (
          <div className="advice">
            <div className="advice-tag">建议</div>
            {advice}
          </div>
        )}

        <div className="sheet-actions">
          <button className="btn ghost" onClick={onClose}>关闭</button>
        </div>
      </div>
    </div>
  )
}
