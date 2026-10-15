-- Supabase Postgres: limpeza automatica diaria dos dados ja recebidos.
create extension if not exists pg_cron with schema pg_catalog;
select cron.schedule('master-monitor-retention','17 3 * * *','select public.mm_cleanup();');
