/// 和 iOS 版对应的几个模型。
///
/// 【为什么字段名用下划线】
///
/// 数据库那边就是下划线命名（sender_id、created_at）。直接照着数据库写，
/// 中间少一层映射 —— 少一层就少一处会写错的地方。
/// 界面上要用的话在组件里现算（比如 preview）。

export type UUID = string

/// 资料（服务器上的 profiles 表）
export interface Profile {
  id: UUID
  username: string | null
  display_name: string
  avatar_seed: number
  avatar_url: string | null
  bio?: string | null
}

/// 一段会话：要么是一对一（对方是 friend_id），要么是群
export interface Conversation {
  id: UUID
  kind: 'direct' | 'group'
  title: string | null
  name: string
  avatarSeed: number
  avatarURL: string | null
  lastMessage: string
  lastTime: string
  unread: number
}

/// 一条消息
export interface Message {
  id: UUID
  sender_id: UUID
  recipient_id: UUID | null
  conversation_id: UUID | null
  body: string
  image_url: string | null
  audio_url: string | null
  audio_seconds: number | null
  polished_with: string | null
  recalled_at: string | null
  created_at: string
  /// 界面上要用的：这条是不是我发的
  mine?: boolean
}
