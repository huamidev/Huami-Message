import { useEffect, useState } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase } from './lib/supabase'
import Login from './screens/Login'
import Home from './screens/Home'

/// 整个网页的入口。
///
/// 现在只做两件事：
///   1. 判断有没有登录（没有就显示登录页）
///   2. 登录了先显示一个占位 —— 会话列表是下一个里程碑
///
/// 【为什么先做登录】
///
/// 它是**所有东西的前提**：没有凭证，服务器一条数据都不会给。
/// 而且它也是踩坑最集中的地方（凭证刷新、会话持久化）。
/// 先把它跑通，后面每一步都能用真实数据验证。
export default function App() {
  const [session, setSession] = useState<Session | null>(null)
  const [ready, setReady] = useState(false)

  useEffect(() => {
    // 先问一次"现在有没有会话"（刷新页面时从 localStorage 恢复）
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session)
      setReady(true)
    })

    // 之后的变化都走这个订阅：登录、退出、**凭证自动刷新**都会触发
    const { data } = supabase.auth.onAuthStateChange((_event, next) => {
      setSession(next)
    })
    return () => data.subscription.unsubscribe()
  }, [])

  // 还没问出来之前什么都不画 —— 不然会先闪一下登录页再跳走
  if (!ready) {
    return <div className="boot" />
  }

  if (!session) {
    return <Login />
  }

  return <Home session={session} />
}
