-- ============================================================================
-- 用户名长度改成 5-15 位 + 释放 huami
-- ============================================================================
-- 跑法：Supabase → SQL Editor → 粘进去 → Run。可以重复跑。

-- ① 长度 5-15（原来是 5-20）
alter table public.profiles drop constraint if exists profiles_username_format;
alter table public.profiles add constraint profiles_username_format
    check (username ~ '^[a-z][a-z0-9]{4,14}$');

-- ② 把 huami 从保留字里放出来（用户要用这个名字）
delete from public.reserved_usernames where name = 'huami';
