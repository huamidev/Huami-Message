import { useEffect, useState } from 'react'
import type { Session } from '@supabase/supabase-js'
import {
  findProfile, sendFriendRequest, loadIncomingRequests, respondToRequest,
  normalizeUsername, usernameProblem,
} from '../lib/api'
import type { Profile } from '../lib/types'
import Avatar from '../components/Avatar'

/// 联系人：加好友 + 处理申请。
///
/// 【为什么把这两件事放一页】
///
/// 用户的心智是"我想加个人"和"有人要加我" —— 这两件事都发生在
/// "和好友有关"的那一刻。分成两个 Tab 的话，他得先想清楚自己属于哪一种。
export default function Contacts({ session }: { session: Session }) {
  const myID = session.user.id

  const [input, setInput] = useState('')
  const [found, setFound] = useState<Profile | null>(null)
  const [searched, setSearched] = useState(false)
  const [busy, setBusy] = useState(false)
  const [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null)

  const [requests, setRequests] = useState<
    { id: string; fromID: string; fromName: string; fromUsername: string; note: string | null }[]
  >([])

  const username = normalizeUsername(input)
  const problem = usernameProblem(username)

  async function refreshRequests() {
    try {
      setRequests(await loadIncomingRequests(myID))
    } catch {
      // 拉不到申请不该打扰用户 —— 顶多少看到一个红点
    }
  }

  useEffect(() => {
    refreshRequests()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [myID])

  async function search(e: React.FormEvent) {
    e.preventDefault()
    if (!username || problem) return
    setBusy(true)
    setNotice(null)
    setFound(null)
    try {
      const profile = await findProfile(username)
      setFound(profile)
      setSearched(true)
    } catch (err) {
      setNotice({ ok: false, text: err instanceof Error ? err.message : '查询失败' })
    } finally {
      setBusy(false)
    }
  }

  async function add() {
    if (!found) return
    setBusy(true)
    try {
      await sendFriendRequest(found.username ?? username, null)
      setNotice({ ok: true, text: `申请已经发给 ${found.display_name} 了，等他同意。` })
      setFound(null)
      setInput('')
      setSearched(false)
    } catch (err) {
      // 服务器会用中文说明原因（已经是好友、对方关掉了申请……），
      // 原样显示比我们自己再翻译一遍准
      setNotice({ ok: false, text: err instanceof Error ? err.message : '发送失败' })
    } finally {
      setBusy(false)
    }
  }

  async function respond(id: string, accept: boolean) {
    setBusy(true)
    try {
      await respondToRequest(id, accept)
      await refreshRequests()
    } catch (err) {
      setNotice({ ok: false, text: err instanceof Error ? err.message : '操作失败' })
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="app">
      <header className="topbar">
        <h1>联系人</h1>
      </header>

      <div className="pad" style={{ overflowY: 'auto', paddingBottom: 24 }}>
        {/* ── 新的朋友 ── */}
        {requests.length > 0 && (
          <section className="card">
            <h3>新的朋友（{requests.length}）</h3>
            {requests.map((r) => (
              <div key={r.id} className="req">
                <Avatar name={r.fromName} seed={r.fromID.charCodeAt(0)} size={40} />
                <div className="req-main">
                  <div className="conv-name">{r.fromName}</div>
                  <div className="muted small">@{r.fromUsername}{r.note ? ` · ${r.note}` : ''}</div>
                </div>
                <button className="btn primary small-btn" disabled={busy} onClick={() => respond(r.id, true)}>
                  同意
                </button>
                <button className="btn ghost small-btn" disabled={busy} onClick={() => respond(r.id, false)}>
                  拒绝
                </button>
              </div>
            ))}
          </section>
        )}

        {/* ── 加好友 ── */}
        <section className="card">
          <h3>加好友</h3>
          <p className="muted small">输入对方的用户名（就是 @ 后面那串）</p>
          <form onSubmit={search} className="row-form">
            <input
              value={input}
              onChange={(e) => { setInput(e.target.value); setSearched(false); setFound(null) }}
              placeholder="@test002"
              autoCapitalize="none"
              autoCorrect="off"
              spellCheck={false}
            />
            <button className="btn primary" type="submit" disabled={busy || !username || !!problem}>
              查找
            </button>
          </form>
          {problem && <p className="msg error">{problem}</p>}

          {found && (
            <div className="req" style={{ marginTop: 12 }}>
              <Avatar name={found.display_name} seed={found.avatar_seed} url={found.avatar_url} size={44} />
              <div className="req-main">
                <div className="conv-name">{found.display_name}</div>
                <div className="muted small">@{found.username}</div>
              </div>
              <button className="btn primary small-btn" disabled={busy} onClick={add}>
                加好友
              </button>
            </div>
          )}

          {!found && searched && !problem && (
            <p className="muted small" style={{ marginTop: 10 }}>
              没有这个人。用户名是大小写无关的，但位数要对。
            </p>
          )}

          {notice && <p className={notice.ok ? 'msg ok' : 'msg error'}>{notice.text}</p>}
        </section>

        {/* ── 我的用户名 ── */}
        <section className="card">
          <h3>我的用户名</h3>
          <p className="my-username">@{myUsernameOf(session)}</p>
          <p className="muted small">
            把这个名字给对方，他就能加你。
            （二维码在下一个里程碑 —— iOS 版已经能扫码了。）
          </p>
        </section>
      </div>
    </div>
  )
}

/// 从会话里取我自己的用户名。
///
/// 邮箱登录的用户在 user_metadata 里不一定有 username ——
/// 拿不到就先显示邮箱前缀，别显示空白。
function myUsernameOf(session: Session): string {
  const meta = session.user.user_metadata as Record<string, unknown> | undefined
  const name = meta?.username
  if (typeof name === 'string' && name) return name
  return (session.user.email ?? '').split('@')[0]
}
