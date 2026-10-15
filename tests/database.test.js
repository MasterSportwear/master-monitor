import test from 'node:test';import assert from 'node:assert/strict';import{PGlite}from'@electric-sql/pglite';import{readFile}from'node:fs/promises';
const migration=await readFile(new URL('../supabase/migrations/20261015193217_master_monitor_schema.sql',import.meta.url),'utf8');
test('Postgres: pareamento atomico, deduplicacao, revogacao, agregacao, RLS e retencao',async()=>{
 const db=new PGlite();try{
 await db.exec('create role anon; create role authenticated; create role service_role bypassrls; create schema auth; create table auth.users(id uuid primary key);');await db.exec(migration);await db.exec(await readFile(new URL('../supabase/migrations/20261015214852_chrome_domains.sql',import.meta.url),'utf8'));
 const uid=crypto.randomUUID(),id=crypto.randomUUID();await db.query('insert into auth.users values($1)',[uid]);await db.query("insert into public.mm_manager_invitations(email) values('gestor@example.com')");assert.equal((await db.query("select public.mm_claim_manager($1,'outro@example.com') claimed",[uid])).rows[0].claimed,false);assert.equal((await db.query("select public.mm_claim_manager($1,'gestor@example.com') claimed",[uid])).rows[0].claimed,true);assert.equal((await db.query("select public.mm_claim_manager($1,'gestor@example.com') claimed",[uid])).rows[0].claimed,false);
 await db.query("insert into public.mm_devices(id,collaborator,sector,label,pairing_hash,pairing_expires_at,created_by)values($1,'Ana','Design','Design 01','code',now()+interval '1 day',$2)",[id,uid]);
 const first=await db.query("select public.mm_pair('code','token','PC-01') result");assert.equal(first.rows[0].result.id,id);assert.equal((await db.query("select public.mm_pair('code','other','PC-02') result")).rows[0].result,null);
 const stamp=new Date().toISOString();const localDay=stamp.slice(0,10);
 const rows=[{event_id:crypto.randomUUID(),kind:'uso',captured_at:stamp,local_day:localDay,local_hour:9,payload:{Horario:stamp,Colaborador:'Ana',Setor:'Design',Computador:'PC-01',Aplicativo:'Corel.exe',Estado:'ativo',Segundos:'5'}},{event_id:crypto.randomUUID(),kind:'desempenho',captured_at:stamp,local_day:localDay,local_hour:9,payload:{Horario:stamp,CPU:'92',RAM:'95.5',Disco:'',DiscoLivreGB:'0'}}];
 const ingest=()=>db.query('select public.mm_ingest($1,$2) result',[id,JSON.stringify(rows)]);
 assert.equal((await ingest()).rows[0].result.inserted,2);assert.equal((await ingest()).rows[0].result.inserted,0);assert.equal((await db.query('select count(*) n from public.mm_records')).rows[0].n,2);
 const report=(await db.query('select public.mm_report($1,$2,null) result',[localDay,localDay])).rows[0].result;assert.equal(report.uso[0].Segundos,5);assert.equal(report.desempenho[0].RAM,95.5);assert.equal(report.desempenho[0].RAM_Pico,95.5);assert.equal(report.desempenho[0].RAM_Amostras,1);assert.equal(report.desempenho[0].RAM_Altas,1);assert.equal(report.desempenho[0].Disco,null);assert.equal(report.desempenho[0].DiscoLivreGB,0);assert.equal(report.raw_count,2);
 await db.exec('set role anon');await assert.rejects(db.query('select * from public.mm_records'),/permission denied/);await assert.rejects(db.query("select public.mm_report('2026-01-01','2026-01-01',null)"),/permission denied/);await db.exec('reset role; set role authenticated');await assert.rejects(db.query('select * from public.mm_devices'),/permission denied/);await db.exec('reset role');
 const rls=await db.query("select count(*) n from pg_class where relname in('mm_managers','mm_manager_invitations','mm_devices','mm_records','mm_settings') and relrowsecurity");assert.equal(rls.rows[0].n,5);
 await db.query('update public.mm_devices set revoked_at=now() where id=$1',[id]);await assert.rejects(ingest(),/Device revoked/);
 await db.query("update public.mm_records set received_at=now()-interval '31 days'");assert.equal((await db.query('select public.mm_cleanup() n')).rows[0].n,2);assert.equal((await db.query('select count(*) n from public.mm_records')).rows[0].n,0);
 }finally{await db.close();}
});

test('Postgres: agrupa dominios por maquina e dia sem alterar totais de aplicativos',async()=>{
 const db=new PGlite();try{
 await db.exec('create role anon; create role authenticated; create role service_role bypassrls; create schema auth; create table auth.users(id uuid primary key);');await db.exec(migration);await db.exec(await readFile(new URL('../supabase/migrations/20261015214852_chrome_domains.sql',import.meta.url),'utf8'));
 const uid=crypto.randomUUID(),id=crypto.randomUUID();await db.query('insert into auth.users values($1)',[uid]);await db.query("insert into public.mm_devices(id,collaborator,sector,label,computer,token_hash,created_by) values($1,'Ana','Design','PC','PC','token',$2)",[id,uid]);
 const records=['drive.google.com','drive.google.com','example.com'].map((domain,i)=>({event_id:crypto.randomUUID(),kind:'dominios',captured_at:'2026-10-15T10:00:0'+i+'-03:00',local_day:'2026-10-15',local_hour:10,payload:{Horario:'2026-10-15T10:00:0'+i+'-03:00',Dominio:domain,Segundos:'5'}}));
 await db.query('select public.mm_ingest($1,$2)',[id,JSON.stringify(records)]);
 const r=(await db.query("select public.mm_report('2026-10-15','2026-10-15',null) r")).rows[0].r;assert.equal(r.dominios.length,2);assert.equal(r.uso.length,0);const drive=r.dominios.find(x=>x.Dominio==='drive.google.com');assert.equal(drive.Segundos,10);assert.equal(drive.Colaborador,'Ana');assert.equal(drive.DeviceId,id);assert.equal(drive.Horario,'2026-10-15T10:00:00-03:00');assert.equal(drive.UltimoHorario,'2026-10-15T10:00:01-03:00');assert.equal(r.raw_count,3);
 }finally{await db.close();}
});
