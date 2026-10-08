-- ============================================================================
-- 群组 · 第一步：只加新表，不碰任何现有数据
-- ============================================================================
--
-- 【为什么分步】
--
-- 群聊需要把"消息属于哪段对话"变成一个显式的东西，
-- 而现在的数据模型是一对一的：messages 上直接写着 sender_id / recipient_id。
--
-- 改成"对话"模型意味着要动**已经存在的消息**（给每条补一个 conversation_id）。
-- 那一步有风险 —— 你手机里那些真实消息不能出任何差错。
--
-- 所以第一步只做**纯新增**：建两张新表，一个字都不改老的。
-- 跑完之后现有功能完全不受影响（App 里也没人用它）。
-- 等 App 那边接好了，再做第二步的迁移。
--
-- 跑法：Supabase → SQL Editor → 粘进去 → Run。可以重复跑。

-- ── 对话 ──────────────────────────────────────────────────────────
--
-- 一对一和群聊**用同一张表**，靠 kind 区分。
--
-- 为什么不建两张表：消息表要指向"这段对话"，如果一对一和群聊是两张表，
-- 消息表就得有两个可空外键（二选一），查询和权限规则都要写两遍。
-- 一张表 + 一个 kind 字段，代码里处处省一半。
create table if not exists public.conversations (
    id          uuid primary key default gen_random_uuid(),
    kind        text not null default 'direct'
                check (kind in ('direct', 'group')),
    -- 群名。一对一为空（一对一的标题就是对方的名字）。
    title       text,
    -- 群头像用的配色种子，和好友头像一个机制
    avatar_seed integer not null default 0,
    -- 谁建的。留着以后做"只有群主能改群名 / 解散"。
    created_by  uuid references public.profiles(id) on delete set null,
    created_at  timestamptz not null default now()
);

-- ── 成员 ──────────────────────────────────────────────────────────
create table if not exists public.conversation_members (
    conversation_id uuid not null references public.conversations(id) on delete cascade,
    user_id         uuid not null references public.profiles(id) on delete cascade,
    role            text not null default 'member'
                    check (role in ('owner', 'member')),
    joined_at       timestamptz not null default now(),
    -- 每个人在这段对话里"读到哪儿了"，未读数从这儿算
    last_read_at    timestamptz not null default now(),
    primary key (conversation_id, user_id)
);

-- 按人查"我参与了哪些对话"是最常用的查询
create index if not exists conversation_members_user
    on public.conversation_members (user_id);

alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;

-- ── 权限规则 ──────────────────────────────────────────────────────
--
-- 核心是一句话：**你只能看见你参与的对话**。
--
-- ⚠️ 这里踩过一个坑，写下来：我一开始在两条策略里**直接写子查询**
-- （`exists (select 1 from conversation_members ...)`），想的是
-- "现算最不容易出错，不冗余就不会有同步问题"。
--
-- 结果整个功能一读就 500：
--
--     infinite recursion detected in policy for relation "conversation_members"
--
-- 因为那条策略保护的**就是** conversation_members，
-- 而策略表达式又要去查 conversation_members —— 自己套自己，无限递归。
--
-- 正确做法是把这个判断包进一个 **security definer** 函数：
-- 函数以属主身份执行，内部**绕过 RLS**，递归就断了。
-- 这也是 Supabase 官方推荐的写法（他们的文档里管这叫
-- "avoiding infinite recursion in RLS policies"）。
--
-- 注意 search_path 必须显式写死。security definer + 不设 search_path
-- 是一个已知的提权风险（别人可以建同名函数把你顶掉）。
create or replace function public.is_conversation_member(conv uuid)
returns boolean
language sql
security definer set search_path = public
stable
as $$
    select exists (
        select 1 from public.conversation_members
        where conversation_id = conv
          and user_id = auth.uid()
    );
$$;

drop policy if exists "conversations visible to members" on public.conversations;
create policy "conversations visible to members"
    on public.conversations for select to authenticated
    using (public.is_conversation_member(id));

drop policy if exists "anyone signed in can create a conversation" on public.conversations;
create policy "anyone signed in can create a conversation"
    on public.conversations for insert to authenticated
    with check (auth.uid() = created_by);

drop policy if exists "members visible to members" on public.conversation_members;
create policy "members visible to members"
    on public.conversation_members for select to authenticated
    using (public.is_conversation_member(conversation_id));

-- ⚠️ 成员表**故意不给直接 insert / delete 的规则**。
--
-- 加人、退群、建群这些动作全部走下面的函数（security definer），
-- 因为"谁能加谁"不是一个能用一行表达式说清的规则：
--   · 建群时，创建者要能一次把自己和朋友们加进去
--   · 但一个普通成员**不能**随便把陌生人拉进你的群
-- 写成一个能直接 insert 的规则，等于把群变成了谁都能往里塞人的开放的桶。
-- 用函数把判断收在一处，比在 RLS 里写复杂的表达式更容易看对。

-- ── 建群 ──────────────────────────────────────────────────────────
--
-- 一次调用完成：建对话 + 把创建者设成 owner + 把朋友加进来。
--
-- 为什么要做成一个函数而不是让客户端发三次请求：
-- 中间失败会留下**没有成员的对话**（谁也看不见、也删不掉），
-- 而且客户端可以跳过"创建者必须是 owner"这一步。放数据库里一次做完最稳。
create or replace function public.create_group(
    group_title text,
    member_usernames text[]
)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
    me         uuid := auth.uid();
    new_id     uuid;
    uname      text;
    target     uuid;
begin
    if me is null then raise exception '请先登录'; end if;
    if coalesce(trim(group_title), '') = '' then raise exception '群名不能为空'; end if;
    if array_length(member_usernames, 1) is null then
        raise exception '至少要拉一个人进来';
    end if;
    -- 先挡一道明显的滥用；真要放开再说
    if array_length(member_usernames, 1) > 100 then
        raise exception '一次最多拉 100 人';
    end if;

    insert into public.conversations (kind, title, created_by)
    values ('group', trim(group_title), me)
    returning id into new_id;

    insert into public.conversation_members (conversation_id, user_id, role)
    values (new_id, me, 'owner')
    on conflict do nothing;

    foreach uname in array member_usernames loop
        select id into target from public.profiles
        where username = lower(trim(both '@' from trim(uname)));

        if target is null then
            -- 直接报错并回滚整次建群。
            -- 不做"跳过找不到的人"—— 那样用户会以为人都拉进来了，
            -- 而群里少了几个人却没有任何提示。
            raise exception '找不到用户名：%', uname;
        end if;

        insert into public.conversation_members (conversation_id, user_id, role)
        values (new_id, target, 'member')
        on conflict do nothing;
    end loop;

    return new_id;
end;
$$;
