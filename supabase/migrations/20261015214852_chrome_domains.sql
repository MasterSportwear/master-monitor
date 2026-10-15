begin;
alter table public.mm_records drop constraint mm_records_kind_check;
alter table public.mm_records add constraint mm_records_kind_check check(kind in ('uso','desempenho','eventos','operacao','dominios'));
create or replace function public.mm_report(p_from date,p_to date,p_device uuid default null)
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
 ), domain_groups as (
 select device_id,max(label) label,local_day,payload->>'Dominio' domain,
 max(collaborator) person,max(sector) sector_name,max(computer) machine,
 min(payload->>'Horario') first_at,max(payload->>'Horario') last_at,
 sum((payload->>'Segundos')::numeric) seconds
 from base where kind='dominios' group by device_id,local_day,payload->>'Dominio'
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
 'dominios',coalesce((select jsonb_agg(jsonb_build_object('DeviceId',device_id,'Rotulo',label,'Horario',first_at,'UltimoHorario',last_at,'Colaborador',person,'Setor',sector_name,'Computador',machine,'Dominio',domain,'Segundos',seconds)) from domain_groups),'[]'::jsonb),
 'desempenho',coalesce((select jsonb_agg(jsonb_build_object('DeviceId',device_id,'Rotulo',label,'Horario',time,'Colaborador',person,'Setor',sector_name,'Computador',machine,'CPU',cpu,'RAM',ram,'Disco',disk,'CPU_Pico',cpu_peak,'RAM_Pico',ram_peak,'Disco_Pico',disk_peak,'CPU_Soma',cpu_sum,'RAM_Soma',ram_sum,'Disco_Soma',disk_sum,'CPU_Amostras',cpu_count,'RAM_Amostras',ram_count,'Disco_Amostras',disk_count,'CPU_Altas',cpu_high,'RAM_Altas',ram_high,'Disco_Altas',disk_high,'DiscoLivreGB',free)) from perf_groups),'[]'::jsonb),
 'eventos',coalesce((select jsonb_agg(x.payload||jsonb_build_object('DeviceId',x.device_id,'Rotulo',x.label)) from (select * from base where kind='eventos' order by captured_at desc limit 1000)x),'[]'::jsonb),
 'operacao',coalesce((select jsonb_agg(x.payload||jsonb_build_object('DeviceId',x.device_id,'Rotulo',x.label)) from (select * from base where kind='operacao' order by captured_at desc limit 1000)x),'[]'::jsonb),
 'eventos_total',(select count(*) from base where kind='eventos'),
 'operacao_total',(select count(*) from base where kind='operacao'),
 'raw_count',(select count(*) from base)
 ) into result;
 return result;
end $$;
commit;
