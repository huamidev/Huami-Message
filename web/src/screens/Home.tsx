import { useCallback, useEffect, useState } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase } from '../lib/supabase'
import { loadConversations } from '../lib/api'
import type { Conversation } from '../lib/types'
import Avatar from '../components/Avatar'
import Chat from './Chat'
import CreateGroup from './CreateGroup'

/// 会话列表 —— 打开 App 看到的第一屏。
///
/// 【为什么这一屏最重要】
///
/// 用户每天打开 App 十几次，绝大多数时候只是想看一眼"有没有人找我"。
/// 所以这一屏要做到两件事：
///   1. **立刻有内容**（所以先画出来，别等网络）
///   2. **自己会更新**（别人发来消息，列表要顶上去 —— 不用手动刷新）
export default function Home({ session }: { session: Session }) {
  const myID = session.user.id
  const [conversations, setConversations] = useState<Conversation[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  /// 打开了哪段会话。用状态切页面，先不引路由库 ——
  /// 网页版只有这一层跳转，引一个路由库是多余的负担。
  const [opened, setOpened] = useState<Conversation | null>(null)
  const [creatingGroup, setCreatingGroup] = useState(false)

  const reload = useCallback(async () => {
    try {
      setConversations(await loadConversations(myID))
      setError(null)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }, [myID])

  useEffect(() => {
    reload()
  }, [reload])

  // 实时：任何人给我发消息、或者我自己发了消息，列表都要重排。
  //
  // 这里图省事，收到任何变化就整体重拉一遍 —— 列表本来就只有几十行，
  // 重拉一次几百毫秒。等以后会话特别多了再改成增量更新。
  useEffect(() => {
    const channel = supabase
      .channel('home-messages')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'messages' }, reload)
      .subscribe()
    return () => {
      supabase.removeChannel(channel)
    }
  }, [reload])

  if (creatingGroup) {
    return (
      <CreateGroup
        friends={conversations ?? []}
        onBack={() => setCreatingGroup(false)}
        onCreated={() => { setCreatingGroup(false); reload() }}
      />
    )
  }

  if (opened) {
    return (
      <Chat
        session={session}
        conversation={opened}
        friends={conversations ?? []}
        onBack={() => setOpened(null)}
        onChanged={reload}
      />
    )
  }

  return (
    <div className="app">
      <header className="topbar">
        <h1>消息</h1>
        <button className="icon-btn" onClick={() => setCreatingGroup(true)} title="发起群聊">
          ＋
        </button>
      </header>

      {error && <p className="msg error pad">{error}</p>}

      {conversations === null && <p className="muted pad">加载中…</p>}

      {conversations?.length === 0 && (
        <div className="empty">
          <div className="empty-icon">💬</div>
          <p>还没有聊天</p>
          <p className="muted small">去「联系人」加个好友就能开始了</p>
        </div>
      )}

      <ul className="conv-list">
        {conversations?.map((c) => (
          <li key={c.id}>
            <button className="conv" onClick={() => setOpened(c)}>
              <Avatar name={c.name} seed={c.avatarSeed} url={c.avatarURL} />
              <div className="conv-main">
                <div className="conv-line">
                  <span className="conv-name">{c.name}</span>
                  <span className="conv-time">{shortTime(c.lastTime)}</span>
                </div>
                <div className="conv-line">
                  <span className="conv-preview">{c.lastMessage || '还没有聊过'}</span>
                  {c.unread > 0 && <span className="badge">{c.unread}</span>}
                </div>
              </div>
            </button>
          </li>
        ))}
      </ul>
    </div>
  )
}

/// 列表里那个时间：今天只显示几点几分，昨天显示"昨天"，更早显示日期。
///
/// 为什么不直接显示完整日期：列表里扫一眼是为了判断"这条新不新"，
/// 年月日那种精确信息反而干扰。
function shortTime(iso: string): string {
  if (!iso) return ''
  const d = new Date(iso)
  const now = new Date()
  const sameDay = d.toDateString() === now.toDateString()
  if (sameDay) {
    return `${d.getHours()}:${String(d.getMinutes()).padStart(2, '0')}`
  }
  const yesterday = new Date(now)
  yesterday.setDate(now.getDate() - 1)
  if (d.toDateString() === yesterday.toDateString()) return '昨天'
  return `${d.getMonth() + 1}/${d.getDate()}`
}
