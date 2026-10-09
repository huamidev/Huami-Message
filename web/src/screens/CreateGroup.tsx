import { useState } from 'react'
import { createGroup } from '../lib/api'
import type { Conversation } from '../lib/types'
import Avatar from '../components/Avatar'

/// 发起群聊：选人 → 起名 → 建。
///
/// 【为什么先选人、再起名】
///
/// 真实的使用顺序就是这样：脑子里先有"要和这几个人说件事"，
/// 群名往往最后才想（甚至建完才改）。
/// 反过来先让人填名字，会卡在"叫什么好呢"这一步 ——
/// 而他真正想做的事是赶紧把那几个人拉进来。
///
/// 所以名字放在后面，而且**预填一个默认名**，不想改可以直接建。
export default function CreateGroup({
  friends,
  onBack,
  onCreated,
}: {
  friends: Conversation[]
  onBack: () => void
  onCreated: () => void
}) {
  const [picked, setPicked] = useState<Set<string>>(new Set())
  const [title, setTitle] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  // 只能拉一对一的好友进来 —— 群不能嵌套群
  const candidates = friends.filter((f) => f.kind === 'direct')

  /// 没填名字就用「我、他、他」当默认名。
  ///
  /// 好处是：**用户永远不用面对一个空的必填项**。
  const effectiveTitle = (() => {
    const trimmed = title.trim()
    if (trimmed) return trimmed
    const names = candidates.filter((c) => picked.has(c.id)).map((c) => c.name)
    const shown = ['我', ...names].slice(0, 4).join('、')
    return names.length + 1 > 4 ? shown + '…' : shown
  })()

  function toggle(id: string) {
    const next = new Set(picked)
    next.has(id) ? next.delete(id) : next.add(id)
    setPicked(next)
  }

  async function create() {
    const chosen = candidates.filter((c) => picked.has(c.id))
    // ⚠️ 用 username，不是 name —— 见 types.ts 里的说明
    const usernames = chosen.map((c) => c.username).filter((u): u is string => !!u)
    if (usernames.length !== chosen.length) {
      setError('有人的用户名还没同步下来，刷新一次再试。')
      return
    }

    setBusy(true)
    setError(null)
    try {
      await createGroup(effectiveTitle, usernames)
      onCreated()
    } catch (err) {
      setError(err instanceof Error ? err.message : '建群失败')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="app">
      <header className="topbar">
        <button className="icon-btn" onClick={onBack}>‹</button>
        <h1 style={{ fontSize: 18 }}>发起群聊</h1>
        <button className="btn primary small-btn" onClick={create} disabled={picked.size === 0 || busy}>
          {busy ? '创建中…' : '创建'}
        </button>
      </header>

      <div className="pad" style={{ overflowY: 'auto', flex: 1, paddingBottom: 16 }}>
        <p className="muted small">
          {picked.size === 0 ? '选要拉进来的人' : `已选 ${picked.size} 人`}
        </p>
        {candidates.map((c) => (
          <button key={c.id} className="req pick" onClick={() => toggle(c.id)}>
            {/* 用勾表示选中，不只靠背景色 —— 色弱的人也看得出来 */}
            <span className={picked.has(c.id) ? 'tick on' : 'tick'}>{picked.has(c.id) ? '✓' : ''}</span>
            <Avatar name={c.name} seed={c.avatarSeed} url={c.avatarURL} size={38} />
            <span className="conv-name">{c.name}</span>
          </button>
        ))}
        {candidates.length === 0 && (
          <p className="muted small">还没有好友。先加一个好友才能建群。</p>
        )}
      </div>

      <div className="composer">
        <input
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          placeholder={effectiveTitle || '群名称'}
        />
      </div>
      {error && <p className="msg error pad">{error}</p>}
    </div>
  )
}
