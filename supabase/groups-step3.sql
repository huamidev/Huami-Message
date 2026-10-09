-- ============================================================================
-- 群组 · 第三步：让群消息读得出来
-- ============================================================================
--
-- 【为什么需要这一步】
--
-- 消息表原来的读规则是：
--
--     using (auth.uid() = sender_id or auth.uid() = recipient_id)
--
-- 而**群消息的 recipient_id 是空的**（它只有 conversation_id）——
-- 第二个条件永远不成立，于是：
--
--     你能读到"自己发的"群消息，但**读不到别人发的**。
--     表现是"两边收不到对面发的消息"，而发送是正常的
--     （插入走的是另一条规则，所以 POST 一直返回 201）。
--
-- 加上第三个条件：**只要我是这个群的成员，就能读这个群的消息**。
-- 判断复用 is_conversation_member()——它内部绕过 RLS，
-- 所以不会像上次那样自己套自己。
--
-- 跑法：Supabase → SQL Editor → 粘进去 → Run。可以重复跑。

drop policy if exists "messages read own" on public.messages;
create policy "messages read own"
    on public.messages for select
    to authenticated
    using (
        auth.uid() = sender_id
        or auth.uid() = recipient_id
        or (
            conversation_id is not null
            and public.is_conversation_member(conversation_id)
        )
    );
