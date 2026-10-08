-- ============================================================================
-- 用户名 · 第 1 步（**现在就可以跑**，不影响正在用的 App）
-- ============================================================================
--
-- 加一列 username、给已有用户自动分配、加上格式和唯一约束、
-- 并把"注册时自动分配"也接上。
--
-- 注意：**邀请码这一列现在先留着。**
-- 因为你现在手机上的 App 还在用它 —— 这步一跑就删，App 会当场坏掉。
-- 删掉它放在第 2 步（等新版本装上去之后）。

-- ── ① 加列 ──
alter table public.profiles add column if not exists username text;

-- ── ② 给已有用户自动分配 ──
--
-- 不分配的话他们没有任何用户名，就加不了好友了。
-- 用 id 派生（不是随机）：**同一个用户每次跑都得到同一个名字**，
-- 所以这个脚本跑多少遍结果都一样，不会因为重跑又换一批名字。
update public.profiles
set username = 'u' || substr(replace(id::text, '-', ''), 1, 10)
where username is null;

-- ── ③ 定规矩 ──
alter table public.profiles alter column username set not null;

-- 唯一。用普通索引就够了：用户名**全部存小写**，所以不用 lower() 索引。
create unique index if not exists profiles_username_key
    on public.profiles (username);

-- 格式：字母开头，只能有小写字母和数字，5 到 20 位。
--
-- 为什么强制小写：用户输入 "Huami" 和 "huami" 在数据库里
-- 必须**算同一个名字**，否则会撞车（两个人一位一个，谁也分不清）。
-- 在入口处统一转小写，比在每个查询里 lower() 干净。
--
-- 为什么必须字母开头：全数字的名字看起来像手机号/ID，
-- 而且容易被拿来冒充系统（比如 "10086"）。
alter table public.profiles drop constraint if exists profiles_username_format;
alter table public.profiles add constraint profiles_username_format
    check (username ~ '^[a-z][a-z0-9]{4,19}$');

-- ── ④ 注册时自动分配（**这一步不能漏**）──
--
-- 上面把 username 设成 not null 了，如果注册时不给，
-- **所有新用户注册都会失败** —— 这是个一跑就炸、但很容易忘的地方。
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
    new_code text;
    new_name text;
begin
    -- 用户名：从 id 派生，保证不重复、且不用循环重试
    new_name := 'u' || substr(replace(new.id::text, '-', ''), 1, 10);

    loop
        new_code := upper(substr(
            translate(replace(gen_random_uuid()::text, '-', ''), '01il', '2345'),
            1, 8));
        exit when not exists (select 1 from public.profiles where invite_code = new_code);
    end loop;

    insert into public.profiles (id, display_name, invite_code, username)
    values (
        new.id,
        coalesce(new.raw_user_meta_data->>'full_name', '我'),
        new_code,
        new_name
    );
    return new;
end;
$$;
