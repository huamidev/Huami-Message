-- ============================================================================
-- 群组 · 第四步：群消息读权限 + 改群名 + 拉人 + 退群
-- ============================================================================
--
-- 跑法：Supabase → SQL Editor → 粘进去 → Run。可以重复跑。

-- ── ① 群消息读权限 ──────────────────────────────────────────────────
--
-- 消息表原来的读规则是 auth.uid() = sender_id or recipient_id，
-- 而群消息的 recipient_id 是空的 —— 第二个条件永远不成立，
-- 于是只能读到"自己发的"群消息。不修的话群里收不到别人发的话。
drop policy if exists "messages read own" on public.messages;
create policy "messages read own"
    on public.messages for select to authenticated
    using (
        auth.uid() = sender_id
        or auth.uid() = recipient_id
        or (
            conversation_id is not null
            and public.is_conversation_member(conversation_id)
        )
    );

-- ── ② 改群名：只有群主 ──────────────────────────────────────────────
--
-- conversations 原来只有 select 和 insert 的规则，没有 update ——
-- 所以改群名会被数据库直接拒掉。
drop policy if exists "owner can rename group" on public.conversations;
create policy "owner can rename group"
    on public.conversations for update to authenticated
    using (created_by = auth.uid())
    with check (created_by = auth.uid());

-- ── ③ 往群里拉人 ────────────────────────────────────────────────────
--
-- 成员表故意没有直接的 insert 权限（见第一步的说明）——
-- 谁能加谁不是一行表达式能说清的，收进函数里。
--
-- 规则：**群里的人才能拉人**；拉谁谁就进来。
-- （和微信一样：群成员可以拉自己的好友进来。）
create or replace function public.add_group_members(
    target_group uuid,
    member_usernames text[]
)
returns boolean
language plpgsql
security definer set search_path = public
as $$
declare
    uname  text;
    target uuid;
begin
    if auth.uid() is null then raise exception '请先登录'; end if;
    if not public.is_conversation_member(target_group) then
        raise exception '你不在这个群里';
    end if;

    foreach uname in array member_usernames loop
        select id into target from public.profiles
        where username = lower(trim(both '@' from trim(uname)));

        if target is null then
            -- 和建群一样：找不到就整次回滚，不做"跳过"。
            -- 跳过的话用户以为人都拉进来了，而群里少了几个人却没有任何提示。
            raise exception '找不到用户名：%', uname;
        end if;

        insert into public.conversation_members (conversation_id, user_id, role)
        values (target_group, target, 'member')
        on conflict do nothing;
    end loop;

    return true;
end;
$$;

-- ── ④ 退群 ──────────────────────────────────────────────────────────
create or replace function public.leave_group(target_group uuid)
returns boolean
language plpgsql
security definer set search_path = public
as $$
declare
    me uuid := auth.uid();
begin
    if me is null then raise exception '请先登录'; end if;

    -- ⚠️ 群主不能直接退。
    --
    -- 退了之后这个群就没人能改名字、没人能管，剩下的人卡在里面出不来
    --（而且他们连"群主是谁"都看不出来）。要退得先转让 ——
    -- 转让功能以后做，现在先把这条路堵上，并给一句能看懂的话。
    if exists (
        select 1 from public.conversations
        where id = target_group and created_by = me
    ) then
        raise exception '你是群主。转让给别人之后才能退群。';
    end if;

    delete from public.conversation_members
    where conversation_id = target_group and user_id = me;

    return true;
end;
$$;
