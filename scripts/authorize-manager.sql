-- Execute uma vez no SQL Editor do projeto apos as migracoes.
-- Substitua o texto abaixo pelo e-mail escolhido para o gestor.
insert into public.mm_manager_invitations(email)
values(lower('SUBSTITUA_PELO_EMAIL_DO_GESTOR'))
on conflict(email) do update set expires_at=now()+interval '7 days',claimed_by=null;
-- O usuario cria a propria senha no Primeiro acesso e confirma seu e-mail.
-- A API so libera o acesso ao e-mail convidado e confirmado pelo Supabase Auth.
