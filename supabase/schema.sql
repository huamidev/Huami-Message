-- ============================================================================
-- Huami Message · 数据库结构
-- ============================================================================
--
-- 用法：Supabase 控制台 → SQL Editor → 把整个文件粘进去 → Run。
-- 可以重复运行（都写了 if not exists / drop policy if exists）。
--
-- 【设计上几个关键决定，先看这段再往下读】
--
-- 1. **消息的 id 由客户端生成**（uuid v4），不是服务器自增。
--    因为我们做了"本地优先"：消息先写进手机本地、立刻显示，再送服务器。
--    如果等服务器分配 id，本地那条和服务器那条就对不上号，
--    "发送中 → 已发送"的状态替换就无从谈起。
--
-- 2. **好友关系存两行**（A→B 和 B→A）。
--    这样每个人都能有自己的 blocked 标记：你拉黑了他，不影响他那边看到你。
--    存一行再查两次虽然省空间，但每次查询都要 OR 两个方向，很容易写错。
--
-- 3. **拉黑在服务器端也拦**（见下面 messages 的 insert 策略）。
--    只在客户端拦是不够的 —— 对方换个客户端、或者直接调接口，照样能发进来。
--
-- 4. **删除要留墓碑**（deletions 表）。
--    否则你在这台手机上删了，换台设备登录，删掉的东西又被同步拉回来了。
--    （这个坑我们在本地数据库那一层已经踩过一次。）
--
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. 用户档案
-- ----------------------------------------------------------------------------
-- 和 Supabase 自带的 auth.users 是一对一。那里放的是登录凭证，
-- 这里放的是"展示给别人看的东西"。

create table if not exists public.profiles (
    id            uuid primary key references auth.users on delete cascade,
    display_name  text        not null,
    avatar_seed   int         not null default 0,
    -- 邀请码：加好友靠它，不走通讯录（通讯录是隐私雷区，审核也容易出问题）
    invite_code   text        unique not null,
    created_at    timestamptz not null default now()
);

-- 注册时自动建档案 + 生成一个不重复的邀请码。
-- 放在数据库里做，而不是让客户端调一次接口 —— 客户端可能失败、可能被绕过。
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
    new_code text;
begin
    loop
        -- ⚠️ 这里特意用 gen_random_uuid()（PostgreSQL 13 起内置），
        --    而不是 gen_random_bytes()（那来自 pgcrypto 扩展，得先装）。
        --    少一个依赖就少一个"注册时报错但不知道为什么"的可能。
        --    顺手把容易看错的 0/O/1/I/l 替换掉 —— 邀请码是要用户手输的。
        new_code := upper(substr(
            translate(replace(gen_random_uuid()::text, '-', ''), '01il', '2345'),
            1, 8));
        exit when not exists (select 1 from public.profiles where invite_code = new_code);
    end loop;

    insert into public.profiles (id, display_name, invite_code)
    values (
        new.id,
        coalesce(new.raw_user_meta_data->>'full_name', '我'),
        new_code
    );
    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();


-- ----------------------------------------------------------------------------
-- 2. 好友关系
-- ----------------------------------------------------------------------------

create table if not exists public.friendships (
    user_id    uuid not null references public.profiles(id) on delete cascade,
    friend_id  uuid not null references public.profiles(id) on delete cascade,
    -- 我是否拉黑了对方（每个人有自己的标记）
    blocked    boolean not null default false,
    created_at timestamptz not null default now(),
    primary key (user_id, friend_id),
    check (user_id <> friend_id)
);

-- 为什么要反过来查？因为"我拉黑了谁"和"谁拉黑了我"是两件事。
create index if not exists friendships_friend_idx on public.friendships (friend_id);


-- ----------------------------------------------------------------------------
-- 3. 消息
-- ----------------------------------------------------------------------------

create table if not exists public.messages (
    id            uuid primary key,                 -- 客户端生成，见开头说明 1
    sender_id     uuid not null references public.profiles(id) on delete cascade,
    recipient_id  uuid not null references public.profiles(id) on delete cascade,
    body          text not null,
    -- 用了哪种润色风格（tactful/concise/warm），没用就是 null。
    -- 存着它，对方那台设备才能显示"这条是 AI 改过的"。
    polished_with text,
    created_at    timestamptz not null default now(),
    check (sender_id <> recipient_id)
);

-- 拉一个会话的历史消息，靠这个索引
create index if not exists messages_pair_idx
    on public.messages (sender_id, recipient_id, created_at desc);
create index if not exists messages_inbox_idx
    on public.messages (recipient_id, created_at desc);


-- ----------------------------------------------------------------------------
-- 4. 举报
-- ----------------------------------------------------------------------------

create table if not exists public.reports (
    id           uuid primary key default gen_random_uuid(),
    reporter_id  uuid not null references public.profiles(id) on delete cascade,
    reported_id  uuid not null references public.profiles(id) on delete cascade,
    reason       text not null,
    note         text,
    created_at   timestamptz not null default now(),
    check (reporter_id <> reported_id)
);

create index if not exists reports_reported_idx on public.reports (reported_id, created_at desc);


-- ----------------------------------------------------------------------------
-- 5. 删除墓碑
-- ----------------------------------------------------------------------------
-- 用户删掉的东西，要能被同步到其他设备。
-- target_id 可能是消息 id，也可能是好友 id。

create table if not exists public.deletions (
    user_id    uuid not null references public.profiles(id) on delete cascade,
    target_id  uuid not null,
    kind       text not null check (kind in ('message', 'friend')),
    deleted_at timestamptz not null default now(),
    primary key (user_id, target_id)
);

create index if not exists deletions_user_idx on public.deletions (user_id, deleted_at desc);


-- ============================================================================
-- 权限规则（Row Level Security）
-- ============================================================================
--
-- 这是整份文件**最重要**的部分。
-- 没有 RLS，任何人拿到 anon key（它是公开的、就写在 App 里）
-- 就能读走整个数据库里所有人的聊天记录。
--
-- 一句话概括下面在做什么：**每个人都只能碰和自己有关的数据。**

alter table public.profiles    enable row level security;
alter table public.friendships enable row level security;
alter table public.messages    enable row level security;
alter table public.reports     enable row level security;
alter table public.deletions   enable row level security;


-- ── profiles ──
-- 读：登录用户都能读（要靠邀请码搜好友，必须能查到别人的名字）
-- 写：只能改自己那行

drop policy if exists "profiles readable by authed" on public.profiles;
create policy "profiles readable by authed"
    on public.profiles for select
    to authenticated
    using (true);

drop policy if exists "profiles update self" on public.profiles;
create policy "profiles update self"
    on public.profiles for update
    to authenticated
    using (auth.uid() = id)
    with check (auth.uid() = id);


-- ── friendships ──
-- 只能看到 / 操作"以我为 user_id"的那些行。
-- 别人拉黑了我，我查不到 —— 这没关系：拉黑本来就不该通知对方。

drop policy if exists "friendships own" on public.friendships;
create policy "friendships own"
    on public.friendships for all
    to authenticated
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);


-- ── messages ──
-- 读：只能读"我是发送方"或"我是接收方"的消息
-- 发：只能以自己的身份发，**并且不能发给一个已经拉黑了我的人**

drop policy if exists "messages read own" on public.messages;
create policy "messages read own"
    on public.messages for select
    to authenticated
    using (auth.uid() = sender_id or auth.uid() = recipient_id);

drop policy if exists "messages send own" on public.messages;
create policy "messages send own"
    on public.messages for insert
    to authenticated
    with check (
        auth.uid() = sender_id
        -- 关键：对方如果拉黑了我，服务器直接拒收。
        -- 只在客户端拦是不够的 —— 对方换个客户端照样能发进来。
        and not exists (
            select 1 from public.friendships f
            where f.user_id = recipient_id
              and f.friend_id = sender_id
              and f.blocked
        )
    );

-- 删除：只能删自己发的（撤回）。"清空聊天记录"是**只删自己这边**，
-- 靠 deletions 墓碑实现，不改对方的库。


-- ── reports ──
-- 只能提交自己的举报，只能看自己提交过的。
-- （处理举报要看内容，那是后台用 service_role 做，不受 RLS 限制。）

drop policy if exists "reports insert own" on public.reports;
create policy "reports insert own"
    on public.reports for insert
    to authenticated
    with check (auth.uid() = reporter_id);

drop policy if exists "reports read own" on public.reports;
create policy "reports read own"
    on public.reports for select
    to authenticated
    using (auth.uid() = reporter_id);


-- ── deletions ──
-- 只能读写自己的墓碑

drop policy if exists "deletions own" on public.deletions;
create policy "deletions own"
    on public.deletions for all
    to authenticated
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);


-- ============================================================================
-- 实时推送
-- ============================================================================
-- 把 messages 加入实时频道，这样对方一发消息，你这边立刻收到。

do $$
begin
    alter publication supabase_realtime add table public.messages;
exception
    when duplicate_object then null;   -- 已经加过了就跳过
end $$;


-- ============================================================================
-- 加好友的函数
-- ============================================================================
-- 加好友要写两行（A→B 和 B→A）。让客户端分两次写不安全也不好回滚，
-- 所以做成一个函数，一次搞定。

create or replace function public.add_friend_by_invite(code text)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
    target_id uuid;
begin
    select id into target_id from public.profiles where invite_code = upper(trim(code));

    if target_id is null then
        raise exception '邀请码不存在';
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


-- ============================================================================
-- 做完之后的检查
-- ============================================================================
-- 在 SQL Editor 里跑这几句，确认建对了：
--
--   select tablename, rowsecurity from pg_tables where schemaname = 'public';
--   -- rowsecurity 必须全是 true，有一个 false 就是数据裸奔
--
--   select tablename from pg_publication_tables where pubname = 'supabase_realtime';
--   -- 应该看到 messages
