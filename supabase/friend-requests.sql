-- ============================================================================
-- 好友申请（微信式）
-- ============================================================================
--
-- 以前是"输用户名 → 直接成为好友"。改成：
--   输用户名 → 看到对方主页 → 发申请 → 对方同意 → 才是好友
--
-- 为什么要改：**直接加好友等于任何人都能往你的好友列表里塞自己。**
-- 用户名是公开的，猜到一个名字就能加，用户连拒绝的机会都没有。
--
-- 跑法：Supabase → SQL Editor → 粘进去 → Run。可以重复跑。

-- ----------------------------------------------------------------------------
-- 1. 申请表
-- ----------------------------------------------------------------------------

create table if not exists public.friend_requests (
    id         uuid primary key default gen_random_uuid(),
    from_id    uuid not null references public.profiles(id) on delete cascade,
    to_id      uuid not null references public.profiles(id) on delete cascade,
    -- 附言（"我是…"）。可以留空：硬要求写一句话会让人卡在这里。
    note       text,
    status     text not null default 'pending'
               check (status in ('pending', 'accepted', 'rejected')),
    created_at timestamptz not null default now(),
    handled_at timestamptz,
    check (from_id <> to_id)
);

-- 同一个人对同一个人，**只能有一条待处理的申请**。
-- 用部分索引（where status = 'pending'）而不是普通唯一索引：
-- 被拒之后应该还能再申请，历史记录也该留着。
create unique index if not exists friend_requests_pending_key
    on public.friend_requests (from_id, to_id)
    where status = 'pending';

-- 收件箱：查"发给我的、还没处理的"
create index if not exists friend_requests_inbox
    on public.friend_requests (to_id, status, created_at desc);

alter table public.friend_requests enable row level security;

-- 发出去的、和发给我的，都看得到。别人的看不到。
drop policy if exists "friend_requests visible to both sides" on public.friend_requests;
create policy "friend_requests visible to both sides"
    on public.friend_requests for select to authenticated
    using (auth.uid() = from_id or auth.uid() = to_id);

-- 只能以自己的名义发。
-- （**不允许直接 update** —— 同意/拒绝必须走下面的函数，
--   因为"同意"还要顺带建立好友关系，两步必须一起成功或一起失败。）
drop policy if exists "friend_requests send as self" on public.friend_requests;
create policy "friend_requests send as self"
    on public.friend_requests for insert to authenticated
    with check (auth.uid() = from_id);


-- ----------------------------------------------------------------------------
-- 2. 发申请
-- ----------------------------------------------------------------------------

create or replace function public.send_friend_request(target_username text, note text default null)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
    me        uuid := auth.uid();
    target_id uuid;
    request_id uuid;
begin
    if me is null then
        raise exception '请先登录';
    end if;

    -- 顺手去掉用户可能带上的 @ 和空格、统一小写
    select id into target_id
    from public.profiles
    where username = lower(trim(both '@' from trim(target_username)));

    if target_id is null then
        raise exception '没有这个人';
    end if;
    if target_id = me then
        raise exception '不能加自己';
    end if;

    -- 已经是好友了就别发申请
    if exists (
        select 1 from public.friendships
        where user_id = me and friend_id = target_id
    ) then
        raise exception '你们已经是好友了';
    end if;

    -- 对方已经申请过我了 —— 那就直接同意，别让两个人互相干等。
    -- 这是实际用起来最常撞到的情况：两个人几乎同时加了对方。
    select id into request_id
    from public.friend_requests
    where from_id = target_id and to_id = me and status = 'pending'
    limit 1;

    if request_id is not null then
        perform public.respond_friend_request(request_id, true);
        return request_id;
    end if;

    -- 我自己已经发过一条待处理的，就复用（避免重复点）
    select id into request_id
    from public.friend_requests
    where from_id = me and to_id = target_id and status = 'pending'
    limit 1;
    if request_id is not null then
        return request_id;
    end if;

    insert into public.friend_requests (from_id, to_id, note)
    values (me, target_id, nullif(trim(coalesce(note, '')), ''))
    returning id into request_id;

    -- 双方自动建立好友关系（否则从没申请过我们的用户，库里会缺一行）
    insert into public.profiles (id, display_name, username)
    select p.id, coalesce(p.display_name, '我'), p.username
    from public.profiles p where p.id in (me, target_id)
    on conflict (id) do nothing;

    -- 发申请者直接建"我→他"的好友关系
    insert into public.friendships (user_id, friend_id)
    values (me, target_id)
    on conflict do nothing;

    return request_id;
end;
$$;


-- ----------------------------------------------------------------------------
-- 3. 同意 / 拒绝
-- ----------------------------------------------------------------------------

create or replace function public.respond_friend_request(request_id uuid, accept boolean)
returns boolean
language plpgsql
security definer set search_path = public
as $$
declare
    req public.friend_requests;
begin
    if auth.uid() is null then
        raise exception '请先登录';
    end if;

    select * into req from public.friend_requests where id = request_id;

    if req.id is null then
        raise exception '找不到这条申请';
    end if;
    -- ⚠️ 只有收件人能处理。少了这一句，**任何人都能替别人同意**。
    if req.to_id <> auth.uid() then
        raise exception '这条申请不是发给你的';
    end if;
    if req.status <> 'pending' then
        return true;   -- 已经处理过了，重复点是正常操作，别报错
    end if;

    update public.friend_requests
    set status = case when accept then 'accepted' else 'rejected' end,
        handled_at = now()
    where id = request_id;

    if accept then
        -- 建立双向好友关系
        insert into public.friendships (user_id, friend_id)
        values (req.from_id, req.to_id), (req.to_id, req.from_id)
        on conflict do nothing;
    end if;

    return true;
end;
$$;
