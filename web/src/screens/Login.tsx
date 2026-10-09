import { useState } from 'react'
import { supabase } from '../lib/supabase'

/// 登录 / 注册。
///
/// 【为什么两个模式放一页，而不是两个页面】
///
/// 用户点进来想做的事只有一件："我要进去"。分成两个页面的话，
/// 他得先判断自己算"登录"还是"注册" —— 而很多人根本分不清
/// （尤其是第一次用的人）。一个切换条最省事。
export default function Login() {
  const [mode, setMode] = useState<'signin' | 'signup'>('signin')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState<string | null>(null)
  const [isError, setIsError] = useState(false)

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    if (busy) return
    setBusy(true)
    setMessage(null)

    // 注册时确认邮件会跳回这个地址。用当前站点，
    // 这样本地跑和部署之后都不用改。
    const redirectTo = window.location.origin

    const { error } =
      mode === 'signin'
        ? await supabase.auth.signInWithPassword({ email, password })
        : await supabase.auth.signUp({ email, password, options: { emailRedirectTo: redirectTo } })

    setBusy(false)
    if (error) {
      setIsError(true)
      setMessage(translate(error.message))
      return
    }
    if (mode === 'signup') {
      setIsError(false)
      setMessage('注册成功。去邮箱点一下确认链接就能进来了。')
    }
  }

  return (
    <div className="auth-page">
      <div className="auth-card">
        <div className="auth-logo">💬</div>
        <h1>Huami Message</h1>
        <p className="muted">帮你把话说好</p>

        <div className="segmented">
          <button
            className={mode === 'signin' ? 'on' : ''}
            onClick={() => { setMode('signin'); setMessage(null) }}
            type="button"
          >
            登录
          </button>
          <button
            className={mode === 'signup' ? 'on' : ''}
            onClick={() => { setMode('signup'); setMessage(null) }}
            type="button"
          >
            注册
          </button>
        </div>

        <form onSubmit={submit}>
          <input
            type="email"
            placeholder="邮箱"
            value={email}
            autoComplete="email"
            onChange={(e) => setEmail(e.target.value)}
            required
          />
          <input
            type="password"
            placeholder="密码"
            value={password}
            autoComplete={mode === 'signin' ? 'current-password' : 'new-password'}
            onChange={(e) => setPassword(e.target.value)}
            required
          />
          <button className="btn primary" type="submit" disabled={busy}>
            {busy ? '请稍等…' : mode === 'signin' ? '登录' : '注册'}
          </button>
        </form>

        {message && <p className={isError ? 'msg error' : 'msg ok'}>{message}</p>}
      </div>
    </div>
  )
}

/// 把服务器的英文错误换成人话。
///
/// 直接把 "Invalid login credentials" 摆给用户看，他只会觉得 App 坏了。
/// 服务器说的话不该原样丢给用户 —— 翻译一遍是最低限度的尊重。
function translate(raw: string): string {
  const text = raw.toLowerCase()
  if (text.includes('invalid login credentials')) return '邮箱或密码不对。'
  if (text.includes('email not confirmed')) return '这个邮箱还没确认。去收件箱点一下确认链接。'
  if (text.includes('already registered')) return '这个邮箱已经注册过了，直接登录就行。'
  if (text.includes('password') && text.includes('6')) return '密码太短了，至少 6 位。'
  if (text.includes('rate limit')) return '试得太频繁了，等一会儿再来。'
  if (text.includes('failed to fetch')) return '连不上服务器。检查一下网络。'
  return raw
}
