import { createClient } from '@supabase/supabase-js'
import { SUPABASE_URL, SUPABASE_KEY } from './config'

/// 全局唯一的 Supabase 客户端。
///
/// 【为什么用它，而不是像 iOS 那样手写 REST】
///
/// iOS 版是自己拼 URL、自己管 token 刷新、自己搭 WebSocket 的 ——
/// 因为那样能完全掌控（而且当时要学的东西少一点）。
///
/// 网页这边没这个必要：supabase-js 把
///   · 登录、注册、发送确认邮件
///   · **凭证过期自动刷新**
///   · 实时订阅（WebSocket）
///   · 文件上传
/// 全都包好了，而且和数据库的权限规则是同一套东西。
///
/// 自己重写一遍只会重犯 iOS 那边踩过的坑（refresh token 轮换、
/// 401 重试、会话持久化……），没有收益。
export const supabase = createClient(SUPABASE_URL, SUPABASE_KEY, {
  auth: {
    // 会话存在 localStorage 里 —— 刷新页面不用重新登录。
    persistSession: true,
    autoRefreshToken: true,
    // 邮件里的确认链接会带着凭证跳回来，这个开关负责把它接住
    detectSessionInUrl: true,
  },
})
