import { useEffect, useState } from 'react'
import type { Session } from '@supabase/supabase-js'
import {
  loadGroupMembers, renameGroup, addGroupMembers, leaveGroup,
} from '../lib/api'
import type { Conversation } from '../lib/types'
import Avatar from '../components/Avatar'

/// 群资料页：群名、成员、拉人、退群。
///
/// 【为什么这一页值得单独做】
///
/// 群里最常被问的三个问题是"这都谁啊""这群叫啥""我怎么退"。
/// 前两个别人问，第三个自己问 —— 而**退群必须能自己做到**，
/// 不然进了不想进的群就只能一直待着。
export default function GroupInfo({
  session,
  group,
  friends,
  onBack,
  onChanged,
}: {
  session: Session
  group: Conversation
  friends: Conversation[]
  onBack: () => void
  onChanged: () => void
}) {
  const myID = session.user.id
  const [members, setMembers] = useState<{ id: string; name: string; avatarSeed: number; role: string }[]>([])
  const [title, setTitle] = useState(group.name)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [picking, setPicking] = useState(false)
  const [picked, setPicked] = useState<Set<string>>(new Set())

  const me = members.find((m) => m.id === myID)
  /// 群主才能改名字。
  ///
  /// 成员还没拉回来时先当作"我不是群主" —— 宁可晚一秒出现按钮，
  /// 也不要让非群主看到一个点了会被拒的入口。
  const iAmOwner = me?.role === 'owner'

  async function reload() {
    try {
      setMembers(await loadGroupMembers(group.id))
    } catch (e) {
      setError(e instanceof Error ? e.message : '拉成员失败')
    }
  }

  useEffect(() => { reload() }, [group.id])

  /// 可以拉进来的人：好友里还不在这个群里的
  const invitable = friends.filter(
    (f) => f.kind === 'direct' && f.username && !members.some((m) => m.id === f.id),
  )

  async function doRename() {
    const trimmed = title.trim()
    if (!trimmed || trimmed === group.name) return
    setBusy(true)
    try {
      await renameGroup(group.id, trimmed)
      onChanged()
    } catch (e) {
      // 失败要把名字改回去 —— 不然界面显示一个没生效的名字
      setTitle(group.name)
      setError(e instanceof Error ? e.message : '改群名失败')
    } finally {
      setBusy(false)
    }
  }

  async function doAdd() {
    const usernames = invitable.filter((f) => picked.has(f.id)).map((f) => f.username!)
    if (!usernames.length) return
    setBusy(true)
    try {
      await addGroupMembers(group.id, usernames)
      setPicked(new Set())
      setPicking(false)
      await reload()
      onChanged()
    } catch (e) {
      setError(e instanceof Error ? e.message : '加人失败')
    } finally {
      setBusy(false)
    }
  }

  async function doLeave() {
    setBusy(true)
    try {
      await leaveGroup(group.id)
      onChanged()
      onBack()
    } catch (e) {
      setError(e instanceof Error ? e.message : '退群失败')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="app overlay-page">
      <header className="topbar">
        <button className="icon-btn" onClick={onBack}>‹</button>
        <h1 style={{ fontSize: 18 }}>群聊信息</h1>
        <span style={{ width: 38 }} />
      </header>

      <div className="pad" style={{ overflowY: 'auto', flex: 1, paddingBottom: 24 }}>
        <section className="card">
          <div className="req">
            <Avatar name={group.name} seed={group.avatarSeed} size={52} />
            {iAmOwner ? (
              <input
                value={title}
                onChange={(e) => setTitle(e.target.value)}
                onBlur={doRename}
                style={{ flex: 1, fontSize: 17, fontWeight: 600 }}
              />
            ) : (
              <span className="conv-name" style={{ flex: 1 }}>{group.name}</span>
            )}
          </div>
          {iAmOwner && <p className="muted small">改完点空白处生效。只有群主能改群名。</p>}
        </section>

        <section className="card">
          <h3>群成员（{members.length}）</h3>
          {members.map((m) => (
            <div key={m.id} className="req">
              <Avatar name={m.name} seed={m.avatarSeed} size={38} />
              <span className="conv-name" style={{ flex: 1 }}>{m.name}</span>
              {m.role === 'owner' && <span className="owner-tag">群主</span>}
              {m.id === myID && <span className="muted small">我</span>}
            </div>
          ))}
          <button className="btn ghost small-btn" style={{ marginTop: 8 }}
                  onClick={() => setPicking((v) => !v)} disabled={invitable.length === 0}>
            {picking ? '收起' : '加人进群'}
          </button>
        </section>

        {picking && (
          <section className="card">
            {invitable.map((f) => (
              <button key={f.id} className="req pick" onClick={() => {
                const next = new Set(picked)
                next.has(f.id) ? next.delete(f.id) : next.add(f.id)
                setPicked(next)
              }}>
                <span className={picked.has(f.id) ? 'tick on' : 'tick'}>{picked.has(f.id) ? '✓' : ''}</span>
                <Avatar name={f.name} seed={f.avatarSeed} url={f.avatarURL} size={38} />
                <span className="conv-name">{f.name}</span>
              </button>
            ))}
            <button className="btn primary" style={{ marginTop: 8 }}
                    onClick={doAdd} disabled={picked.size === 0 || busy}>加入</button>
          </section>
        )}

        <section className="card">
          {iAmOwner ? (
            // 群主不给退群按钮 —— 直接给一句解释，
            // 而不是给一个点了会报错的按钮
            <p className="muted small">你是群主。转让给别人之后才能退群。</p>
          ) : (
            <button className="btn danger" onClick={doLeave} disabled={busy} style={{ width: '100%' }}>
              {busy ? '处理中…' : '退出群聊'}
            </button>
          )}
        </section>

        {error && <p className="msg error">{error}</p>}
      </div>
    </div>
  )
}
