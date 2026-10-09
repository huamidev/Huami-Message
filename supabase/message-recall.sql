-- ============================================================================
-- 撤回消息
-- ============================================================================
--
-- 【为什么撤回不是"删掉"】
--
-- 删掉的话，对面手机上那条消息**还在** —— 他会看到一个自己记得、
-- 你却坚称没发过的东西。真正要的效果是"两边都变成一条提示"：
--
--     你撤回了一条消息   /   对方撤回了一条消息
--
-- 所以撤回是**打一个标记**，不是删数据。
--
-- 【为什么要加时限】
--
-- 两分钟。和微信一样。没有时限的话，你可以把半年前说过的话悄悄抹掉，
-- 而对方那边的"历史"就变成了不可信的东西 —— 聊天记录之所以有用，
-- 前提是它不会被单方面改写。
--
-- 时限在**客户端**判断（给用户即时反馈），但**服务器也判断一次** ——
-- 客户端可以被绕过，服务器是最后一道。
--
-- 跑法：Supabase → SQL Editor → 粘进去 → Run。可以重复跑。

-- ① 加一列：什么时候撤回的。为空 = 没撤回。
alter table public.messages
    add column if not exists recalled_at timestamptz;

-- ② 只有发消息的人能撤回自己的消息，而且**只有两分钟内**。
drop policy if exists "messages recall own" on public.messages;
create policy "messages recall own"
    on public.messages for update
    to authenticated
    using (
        auth.uid() = sender_id
        and created_at > now() - interval '2 minutes'
    )
    with check (
        auth.uid() = sender_id
        and recalled_at is not null
    );

-- ③ 让实时推送也带上这一列（改动行时前端能收到）
--    ⚠️ 如果这行报"already member"，说明表已经在 publication 里，跳过即可。
-- alter publication supabase_realtime add table public.messages;
