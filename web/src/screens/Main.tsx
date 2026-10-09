import { useState } from 'react'
import type { Session } from '@supabase/supabase-js'
import Home from './Home'
import Contacts from './Contacts'
import Me from './Me'

/// 主界面：底部三个 Tab。
///
/// 【为什么先做「消息」和「联系人」，「我」先放一个占位】
///
/// 「我」那一页主要是设置项，功能上不挡路；
/// 而没有「联系人」就加不了好友 —— 那是真的用不起来。
/// 先把挡路的做完。
type Tab = 'messages' | 'contacts' | 'me'

export default function Main({ session }: { session: Session }) {
  const [tab, setTab] = useState<Tab>('messages')

  return (
    <div className="shell">
      <div className="shell-body">
        {tab === 'messages' && <Home session={session} />}
        {tab === 'contacts' && <Contacts session={session} />}
        {tab === 'me' && <Me session={session} />}
      </div>

      <nav className="tabbar">
        <TabButton on={tab === 'messages'} label="消息" icon="💬" onClick={() => setTab('messages')} />
        <TabButton on={tab === 'contacts'} label="联系人" icon="👥" onClick={() => setTab('contacts')} />
        <TabButton on={tab === 'me'} label="我" icon="🙂" onClick={() => setTab('me')} />
      </nav>
    </div>
  )
}

function TabButton({
  on, label, icon, onClick,
}: { on: boolean; label: string; icon: string; onClick: () => void }) {
  return (
    <button className={on ? 'tab on' : 'tab'} onClick={onClick}>
      <span className="tab-icon">{icon}</span>
      <span className="tab-label">{label}</span>
    </button>
  )
}
