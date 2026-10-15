begin;
create table public.mm_managers (
 user_id uuid primary key references auth.users(id) on delete cascade,
 enabled boolean not null default true,
 created_at timestamptz not null default now()
);
create table public.mm_manager_invitations (
 email text primary key check(email=lower(email)),
 expires_at timestamptz not null default now()+interval '7 days',
 claimed_by uuid references auth.users(id)
);
create table public.mm_devices (
 id uuid primary key,
 collaborator text not null check (length(collaborator) between 1 and 100),
 sector text not null check (length(sector) between 1 and 100),
 label text not null check (length(label) between 1 and 100),
 computer text,
 pairing_hash text unique,
 pairing_expires_at timestamptz,
 token_hash text unique,
 revoked_at timestamptz,
 last_seen_at timestamptz,
 last_sample_at timestamptz,
 created_at timestamptz not null default now(),
 created_by uuid not null references auth.users(id)
);
create table public.mm_records (
 device_id uuid not null references public.mm_devices(id),
 event_id uuid not null,
 kind text not null check (kind in ('uso','desempenho','eventos','operacao')),
 captured_at timestamptz not null,
 local_day date not null,
 local_hour smallint not null check(local_hour between 0 and 23),
 payload jsonb not null check(jsonb_typeof(payload) = 'object'),
 received_at timestamptz not null default now(),
 primary key(device_id,event_id)
);
create index mm_records_report_idx on public.mm_records(local_day,device_id,kind);
create index mm_records_received_idx on public.mm_records(received_at);
create table public.mm_settings (
 singleton boolean primary key default true check(singleton),
 retention_days integer not null default 30 check(retention_days between 7 and 365)
);
insert into public.mm_settings(singleton) values (true);
alter table public.mm_managers enable row level security;
alter table public.mm_manager_invitations enable row level security;
alter table public.mm_devices enable row level security;
alter table public.mm_records enable row level security;
alter table public.mm_settings enable row level security;
revoke all on public.mm_managers,public.mm_manager_invitations,public.mm_devices,public.mm_records,public.mm_settings from anon, authenticated;
grant all on public.mm_managers,public.mm_manager_invitations,public.mm_devices,public.mm_records,public.mm_settings to service_role;
create function public.mm_claim_manager(p_user uuid,p_email text) returns boolean
language plpgsql security invoker set search_path='' as $$
declare n integer;
begin
 update public.mm_manager_invitations set claimed_by=p_user
 where email=lower(p_email) and expires_at>now() and claimed_by is null;
 get diagnostics n=row_count;
 if n=0 then return false; end if;
 insert into public.mm_managers(user_id) values(p_user) on conflict(user_id) do nothing;
 return (select enabled from public.mm_managers where user_id=p_user);
end $$;
revoke all on function public.mm_claim_manager(uuid,text) from public,anon,authenticated;
grant execute on function public.mm_claim_manager(uuid,text) to service_role;
-- Sem politicas para clientes. A API verifica gestor ou credencial de maquina.
create function public.mm_pair(p_pair_hash text,p_token_hash text,p_computer text)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare d public.mm_devices;
begin
 update public.mm_devices set token_hash=p_token_hash,pairing_hash=null,pairing_expires_at=null,
 computer=p_computer,last_seen_at=now()
 where pairing_hash=p_pair_hash and pairing_expires_at>now() and revoked_at is null and token_hash is null returning * into d;
 if d.id is null then return null; end if;
 return jsonb_build_object('id',d.id,'collaborator',d.collaborator,'sector',d.sector,'computer',d.computer,'label',d.label);
end $$;
create function public.mm_ingest(p_device uuid,p_records jsonb)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare n integer; last_at timestamptz;
begin
 -- O lock serializa revogacao e ingestao da mesma maquina.
 perform 1 from public.mm_devices where id=p_device and revoked_at is null and token_hash is not null for update;
 if not found then raise exception 'Device revoked' using errcode='42501'; end if;
 if jsonb_typeof(p_records)<>'array' or jsonb_array_length(p_records)>500 then raise exception 'Invalid batch'; end if;
 insert into public.mm_records(device_id,event_id,kind,captured_at,local_day,local_hour,payload)
 select p_device,x.event_id,x.kind,x.captured_at,x.local_day,x.local_hour,x.payload
 from jsonb_to_recordset(p_records) as x(event_id uuid,kind text,captured_at timestamptz,local_day date,local_hour smallint,payload jsonb)
 on conflict(device_id,event_id) do nothing;
 get diagnostics n = row_count;
 select max(x.captured_at) into last_at from jsonb_to_recordset(p_records) as x(captured_at timestamptz);
 update public.mm_devices set last_seen_at=now(),last_sample_at=greatest(last_sample_at,last_at) where id=p_device;
 return jsonb_build_object('inserted',n,'acknowledged',jsonb_array_length(p_records));
end $$;
create function public.mm_report(p_from date,p_to date,p_device uuid default null)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare result jsonb;
begin
 if p_to<p_from or p_to-p_from>30 then raise exception 'Maximum 31 days'; end if;
 with base as materialized (
 select r.*,d.label,d.computer,d.collaborator,d.sector from public.mm_records r join public.mm_devices d on d.id=r.device_id
 where r.local_day between p_from and p_to and (p_device is null or r.device_id=p_device)
 ), usage_groups as (
 select device_id,max(label) label,local_day,local_hour,payload->>'Aplicativo' app,payload->>'Estado' state,
 payload->>'Colaborador' person,payload->>'Setor' sector_name,payload->>'Computador' machine,
 sum((payload->>'Segundos')::numeric) seconds from base where kind='uso'
 group by device_id,local_day,local_hour,payload->>'Aplicativo',payload->>'Estado',payload->>'Colaborador',payload->>'Setor',payload->>'Computador'
 ), perf_groups as (
 select device_id,local_day,local_hour, floor(extract(minute from captured_at)/5) bucket,
 min(payload->>'Horario') time,max(label) label, max(collaborator) person,max(sector) sector_name,max(computer) machine,
 avg(nullif(payload->>'CPU','')::numeric) cpu,avg(nullif(payload->>'RAM','')::numeric) ram,
 avg(nullif(payload->>'Disco','')::numeric) disk,
 max(nullif(payload->>'CPU','')::numeric) cpu_peak,max(nullif(payload->>'RAM','')::numeric) ram_peak,max(nullif(payload->>'Disco','')::numeric) disk_peak,
 sum(nullif(payload->>'CPU','')::numeric) cpu_sum,sum(nullif(payload->>'RAM','')::numeric) ram_sum,sum(nullif(payload->>'Disco','')::numeric) disk_sum,
 count(nullif(payload->>'CPU','')) cpu_count,count(nullif(payload->>'RAM','')) ram_count,count(nullif(payload->>'Disco','')) disk_count,
 count(*) filter(where nullif(payload->>'CPU','')::numeric>=90) cpu_high,count(*) filter(where nullif(payload->>'RAM','')::numeric>=90) ram_high,count(*) filter(where nullif(payload->>'Disco','')::numeric>=90) disk_high,
 min(nullif(payload->>'DiscoLivreGB','')::numeric) free
 from base where kind='desempenho' group by device_id,local_day,local_hour,floor(extract(minute from captured_at)/5)
 )
 select jsonb_build_object(
 'uso',coalesce((select jsonb_agg(jsonb_build_object('DeviceId',device_id,'Rotulo',label,'Horario',local_day::text||'T'||lpad(local_hour::text,2,'0')||':00:00','Colaborador',person,'Setor',sector_name,'Computador',machine,'Aplicativo',app,'Estado',state,'Segundos',seconds)) from usage_groups),'[]'::jsonb),
 'desempenho',coalesce((select jsonb_agg(jsonb_build_object('DeviceId',device_id,'Rotulo',label,'Horario',time,'Colaborador',person,'Setor',sector_name,'Computador',machine,'CPU',cpu,'RAM',ram,'Disco',disk,'CPU_Pico',cpu_peak,'RAM_Pico',ram_peak,'Disco_Pico',disk_peak,'CPU_Soma',cpu_sum,'RAM_Soma',ram_sum,'Disco_Soma',disk_sum,'CPU_Amostras',cpu_count,'RAM_Amostras',ram_count,'Disco_Amostras',disk_count,'CPU_Altas',cpu_high,'RAM_Altas',ram_high,'Disco_Altas',disk_high,'DiscoLivreGB',free)) from perf_groups),'[]'::jsonb),
 'eventos',coalesce((select jsonb_agg(x.payload||jsonb_build_object('DeviceId',x.device_id,'Rotulo',x.label)) from (select * from base where kind='eventos' order by captured_at desc limit 1000)x),'[]'::jsonb),
 'operacao',coalesce((select jsonb_agg(x.payload||jsonb_build_object('DeviceId',x.device_id,'Rotulo',x.label)) from (select * from base where kind='operacao' order by captured_at desc limit 1000)x),'[]'::jsonb),
 'eventos_total',(select count(*) from base where kind='eventos'),
 'operacao_total',(select count(*) from base where kind='operacao'),
 'raw_count',(select count(*) from base)
 ) into result;
 return result;
end $$;
create function public.mm_cleanup() returns bigint language plpgsql security invoker set search_path='' as $$
declare n bigint;
begin
 delete from public.mm_records where received_at < now() - (select retention_days from public.mm_settings where singleton)*interval '1 day';
 get diagnostics n=row_count; return n;
end $$;
revoke all on function public.mm_pair(text,text,text),public.mm_ingest(uuid,jsonb),public.mm_report(date,date,uuid),public.mm_cleanup() from public,anon,authenticated;
grant execute on function public.mm_pair(text,text,text),public.mm_ingest(uuid,jsonb),public.mm_report(date,date,uuid),public.mm_cleanup() to service_role;
commit;
