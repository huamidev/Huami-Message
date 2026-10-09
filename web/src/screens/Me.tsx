import { useEffect, useRef, useState } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase } from '../lib/supabase'
import { loadMyProfile, updateProfile, uploadAvatar, compressImage } from '../lib/api'
import type { Profile } from '../lib/types'
import Avatar from '../components/Avatar'

/// 「我」这一页：改昵称、换头像、看自己的用户名。
///
/// 【为什么用户名不能改】
///
/// 它是别人找到你的那个名字 —— 改了之后，所有把你记在通讯录里的人
/// 都会找不到你。要让"改用户名"不伤人，得先有一套"曾用名/跳转"的机制，
/// 那是另一个功能。
///
/// 界面上就把这一点说清楚，而不是给一个灰着的输入框让人猜。
export default function Me({ session }: { session: Session }) {
  const myID = session.user.id
  const [profile, setProfile] = useState<Profile | null>(null)
  const [name, setName] = useState('')
  const [busy, setBusy] = useState(false)
  const [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null)
  const fileRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    loadMyProfile(myID).then((p) => {
      setProfile(p)
      setName(p?.display_name ?? '')
    }).catch(() => {})
  }, [myID])

  async function saveName() {
    const trimmed = name.trim()
    if (!trimmed || trimmed === profile?.display_name) return
    setBusy(true)
    try {
      await updateProfile({ display_name: trimmed })
      setProfile((p) => (p ? { ...p, display_name: trimmed } : p))
      setNotice({ ok: true, text: '昵称已更新。' })
    } catch (e) {
      setName(profile?.display_name ?? '')     // 失败要改回去，别显示一个没生效的名字
      setNotice({ ok: false, text: e instanceof Error ? e.message : '改名失败' })
    } finally {
      setBusy(false)
    }
  }

  async function changeAvatar(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    e.target.value = ''
    if (!file) return
    setBusy(true)
    setNotice(null)
    try {
      // 头像统一压成 512 的方图 —— 不压的话一张手机原图就几 MB，
      // 而它只显示在几十像素的地方
      const blob = await compressImage(file)
      const url = await uploadAvatar(myID, blob)
      await updateProfile({ avatar_url: url })
      setProfile((p) => (p ? { ...p, avatar_url: url } : p))
      setNotice({ ok: true, text: '头像已更新。' })
    } catch (err) {
      setNotice({ ok: false, text: err instanceof Error ? err.message : '换头像失败' })
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="app">
      <header className="topbar"><h1>我</h1></header>

      <div className="pad" style={{ overflowY: 'auto', paddingBottom: 96 }}>
        <section className="card" style={{ textAlign: 'center' }}>
          <button
            className="avatar-btn"
            onClick={() => fileRef.current?.click()}
            disabled={busy}
            title="换头像"
          >
            <Avatar
              name={profile?.display_name ?? '?'}
              seed={profile?.avatar_seed ?? 0}
              url={profile?.avatar_url}
              size={76}
            />
            <span className="avatar-hint">{busy ? '…' : '换'}</span>
          </button>
          <input
            ref={fileRef} type="file" accept="image/*"
            style={{ display: 'none' }} onChange={changeAvatar}
          />
        </section>

        <section className="card">
          <h3>昵称</h3>
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
            onBlur={saveName}
            placeholder="别人看到的名字"
          />
          <p className="muted small" style={{ marginTop: 6 }}>改完点空白处生效。</p>
        </section>

        <section className="card">
          <h3>用户名</h3>
          <p className="my-username">@{profile?.username ?? '…'}</p>
          <p className="muted small">
            这是别人找到你的名字，不能改 ——
            改了之后，所有把你存在通讯录里的人都会找不到你。
          </p>
        </section>

        <section className="card">
          <h3>账号</h3>
          <p className="muted small">{session.user.email}</p>
        </section>

        {notice && <p className={notice.ok ? 'msg ok' : 'msg error'}>{notice.text}</p>}

        <section className="card">
          <button className="btn ghost" style={{ width: '100%' }}
                  onClick={() => supabase.auth.signOut()}>
            退出登录
          </button>
        </section>
      </div>
    </div>
  )
}
