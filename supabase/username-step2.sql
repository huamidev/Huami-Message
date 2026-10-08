-- ============================================================================
-- 用户名 · 第 2 步（**等新版本 App 装上去之后再跑**）
-- ============================================================================
--
-- 这一步做的事情不可逆：删掉邀请码那一列。
-- 所以顺序是「先装新 App → 再跑这个」，反了会让旧 App 当场坏掉。

-- ── ① 加好友改成用用户名 ──
create or replace function public.add_friend_by_username(name text)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
    target_id uuid;
    cleaned text;
begin
    -- 顺手把用户可能带上的 @ 和空格去掉、统一小写。
    -- 用户从别人签名里复制过来时，常常连着 @ 一起复制。
    cleaned := lower(trim(both '@' from trim(name)));

    select id into target_id from public.profiles where username = cleaned;

    if target_id is null then
        -- 文案要**能照做**：「没有这个人」比「函数返回空」有用得多，
        -- 而且 App 那边就是靠这句话判断该显示什么的。
        raise exception '没有这个人';
    end if;
    if target_id = auth.uid() then
        raise exception '不能加自己';
    end if;

    insert into public.friendships (user_id, friend_id) values (auth.uid(), target_id)
        on conflict do nothing;
    insert into public.friendships (user_id, friend_id) values (target_id, auth.uid())
        on conflict do nothing;

    return target_id;
end;
$$;

-- ── ② 去掉旧的入口 ──
drop function if exists public.add_friend_by_invite(text);

-- ── ③ 注册时不再生成邀请码 ──
--
-- ⚠️ **必须在删列之前改。**
-- 不改的话，handle_new_user 还会往 invite_code 里插值，
-- 而那一列已经不存在了 —— 结果是**所有新用户注册都失败**，
-- 而且报错发生在触发器里，很难联想到是这个原因。
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
    new_name text;
begin
    -- 用户名从 id 派生：不用循环重试，也永远不会撞车
    new_name := 'u' || substr(replace(new.id::text, '-', ''), 1, 10);

    insert into public.profiles (id, display_name, username)
    values (
        new.id,
        coalesce(new.raw_user_meta_data->>'full_name', '我'),
        new_name
    );
    return new;
end;
$$;

-- ── ④ 删列 ──
alter table public.profiles drop column if exists invite_code;
