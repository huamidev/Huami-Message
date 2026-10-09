import { useEffect, useState } from 'react'
import type { Session } from '@supabase/supabase-js'
import {
  findProfile, sendFriendRequest, loadIncomingRequests, respondToRequest,
  normalizeUsername, usernameProblem, loadMyProfile,
} from '../lib/api'
import QRCode from 'qrcode'
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

  /// 我自己的用户名（从 profiles 查，不是从登录会话猜）
  const [myUsername, setMyUsername] = useState<string | null>(null)
  /// 二维码图片（data URL）
  const [qr, setQr] = useState<string | null>(null)

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
    // 我的用户名 + 我的二维码
    loadMyProfile(myID)
      .then(async (profile) => {
        const name = profile?.username
        if (!name) return
        setMyUsername(name)
        // 二维码里装的是**链接**不是纯用户名：
        // 系统相机扫到链接会直接打开 App 并落到"加好友"，
        // 扫到一串纯文字只会显示出来。（iOS 版同一条链接格式）
        setQr(await QRCode.toDataURL(`huami://add?u=${name}`, {
          width: 220, margin: 1,
          color: { dark: '#1a1a1a', light: '#ffffff' },
        }))
      })
      .catch(() => { /* 拿不到就不显示这一块，不打扰用户 */ })

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

        {/* ── 我的二维码 ── */}
        <section className="card" style={{ textAlign: 'center' }}>
          <h3 style={{ textAlign: 'left' }}>我的二维码</h3>
          {qr ? (
            <>
              <img src={qr} alt="我的二维码" style={{ width: 190, height: 190, margin: '6px auto' }} />
              <p className="my-username">@{myUsername}</p>
              <p className="muted small">
                让对方用相机扫这个码，会自动打开 App 并落到「加好友」。
              </p>
            </>
          ) : (
            <p className="muted small">二维码要等资料加载出来…</p>
          )}
        </section>
      </div>
    </div>
  )
}

