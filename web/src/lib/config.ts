/// 服务器配置。
///
/// 【这两个值是"可以公开"的】
///
/// 这不是密钥 —— Supabase 的 URL 和 publishable key 设计上就是给浏览器用的，
/// 任何人打开开发者工具都能看到。**真正保护数据的是数据库那边的权限规则
///（RLS）**：没有登录、或者不是这条消息的收发双方，服务器一条都不会给。
///
/// 所以它可以写在这里，也可以写进 git —— 不像 service_role key 那种
/// 一旦泄露就等于把整个数据库交出去的东西（那个永远不能出现在前端）。
///
/// 想换服务器的话，用 .env.local 覆盖：
///     VITE_SUPABASE_URL=...
///     VITE_SUPABASE_KEY=...
export const SUPABASE_URL =
  import.meta.env.VITE_SUPABASE_URL ?? 'https://ijfwgbfnyvxfwiizrsit.supabase.co'

export const SUPABASE_KEY =
  import.meta.env.VITE_SUPABASE_KEY ?? 'sb_publishable_t-fmA-s068dhTlpNKRMFxg_iYgsIROa'
