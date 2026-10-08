-- ============================================================================
-- 删除好友（双向）
-- ============================================================================
--
-- 【为什么必须做成数据库函数，而不是客户端直接发 DELETE】
--
-- 好友关系在数据库里存**两行**（我→他、他→我）。
-- 而权限规则只允许改「user_id = 我」的行 —— 客户端**删不掉对方那一行**。
--
-- 如果客户端只删掉自己那行，结果是：
--   我这边看不到他了，他那边还留着我，而且他还能继续给我发消息。
-- 那就不叫"删除好友"了。
--
-- 所以要做成一个 security definer 的函数，在服务端一次删两行。
--
-- 跑法：Supabase → SQL Editor → 粘进去 → Run。可以重复跑。

create or replace function public.remove_friend(target uuid)
returns boolean
language plpgsql
security definer set search_path = public
as $$
begin
    if auth.uid() is null then
        raise exception '请先登录';
    end if;

    if target = auth.uid() then
        raise exception '不能删自己';
    end if;

    delete from public.friendships
    where (user_id = auth.uid() and friend_id = target)
       or (user_id = target and friend_id = auth.uid());

    -- 返回 true 而不是 void：
    -- PostgREST 对 void 返回 204 空响应，客户端解码会失败。
    -- 有个返回值，两边都好写。
    return true;
end;
$$;
