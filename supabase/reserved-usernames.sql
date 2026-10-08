-- ============================================================================
-- 保留用户名
-- ============================================================================
--
-- 【为什么要单独一个文件、而不是写死在格式约束里】
--
-- 写进 CHECK 里的话，每加一个词都要"改约束" —— 那会重建索引、锁表，
-- 而且写错一次整个表就写不进去了。
-- 放进表里之后，加词就是一句 insert，随时能加，不影响任何人。
--
-- 类别是照着"有人会怎么冒充你"想的：
--   1. 系统/官方感的名字 —— 用来骗你朋友"这是官方通知"
--   2. 和产品自己重名的 —— 冒充官方账号
--   3. 容易和系统提示混淆的 —— 比如有人在群里叫 "everyone"
--   4. 别家产品的名字 —— 冒充客服最常见的手法
--
-- 跑法：Supabase → SQL Editor → 粘进去 → Run。可以重复跑。

create table if not exists public.reserved_usernames (
    name text primary key
);

insert into public.reserved_usernames (name) values
    -- 1. 系统 / 官方感的
    ('admin'), ('administrator'), ('root'), ('system'), ('sysadmin'),
    ('support'), ('help'), ('helpdesk'), ('service'), ('services'),
    ('official'), ('staff'), ('team'), ('moderator'), ('mod'),
    ('owner'), ('operator'), ('security'), ('verify'), ('verified'),
    ('account'), ('accounts'), ('billing'), ('payment'), ('notice'),
    ('notification'), ('notifications'), ('alert'), ('alerts'),

    -- 2. 和产品自己重名
    ('huami'), ('huamidev'), ('huamimessage'), ('huamihelp'),
    ('huamiteam'), ('xiaozhushou'),

    -- 3. 容易和系统提示混淆
    ('everyone'), ('here'), ('all'), ('channel'), ('group'),
    ('me'), ('you'), ('null'), ('undefined'), ('anonymous'),

    -- 4. 别家产品（冒充客服最常用）
    ('telegram'), ('wechat'), ('weixin'), ('qq'), ('weibo'),
    ('whatsapp'), ('deepseek'), ('openai'), ('apple'), ('tencent')
on conflict (name) do nothing;

-- 检查函数：用户名不能是保留字
create or replace function public.check_username_reserved()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
    if new.username is not null
       and exists (
           select 1 from public.reserved_usernames r
           where r.name = lower(new.username)
       )
    then
        -- 把话说清楚：用户看到「这个用户名被保留了，换一个」才知道该干嘛，
        -- 看到「违反约束 profiles_username_not_reserved」只会一脸问号。
        raise exception '这个用户名被保留了，换一个';
    end if;
    return new;
end;
$$;

drop trigger if exists profiles_username_not_reserved on public.profiles;
create trigger profiles_username_not_reserved
    before insert or update of username on public.profiles
    for each row execute function public.check_username_reserved();
