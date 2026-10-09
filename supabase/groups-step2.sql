-- ============================================================================
-- 群组 · 第二步：给 messages 加一个可空的 conversation_id
-- ============================================================================
--
-- 【为什么不重建消息表】
--
-- 干净的做法是"消息属于对话"，把 sender_id / recipient_id 去掉。
-- 但那要求**改写你已经存在的每一条消息** —— 那是你和朋友真的说过的话，
-- 跑挂了就没了。为了模型干净去冒这个险，不值得。
--
-- 所以两条路并存：
--   一对一的旧消息（以及将来的）→ recipient_id 有值，conversation_id 为 NULL
--   群消息                     → recipient_id 为 NULL，conversation_id 有值
--
-- 这一段是**纯新增一列**，一个字都不改现有数据。
-- 跑完之后现有功能完全不受影响。
--
-- 跑法：Supabase → SQL Editor → 粘进去 → Run。可以重复跑。

alter table public.messages
    add column if not exists conversation_id uuid
    references public.conversations(id) on delete cascade;

-- 群聊里最常用的查询是"这个群最近的消息"，按时间和会话排
create index if not exists messages_conversation_recent
    on public.messages (conversation_id, created_at desc)
    where conversation_id is not null;

-- 一条消息不能既是私聊又是群聊。用约束把这件事钉死，
-- 免得以后某处写错了两边都填上，出现"一条消息属于两个地方"的怪状态。
alter table public.messages
    drop constraint if exists messages_one_target;
alter table public.messages
    add constraint messages_one_target
    check (not (recipient_id is not null and conversation_id is not null));

-- 反过来也要有：总得有个去处，不能两边都空。
-- （recipient_id 在旧表里本来就是 not null，所以这条主要是保护新路径）
alter table public.messages
    drop constraint if exists messages_has_target;
alter table public.messages
    add constraint messages_has_target
    check (recipient_id is not null or conversation_id is not null);
