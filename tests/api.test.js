import test from 'node:test';import assert from 'node:assert/strict';
import {createHandler,hash,normalizeRecords,secret} from '../supabase/functions/monitor-api/handler.js';
const device={id:'10000000-0000-4000-8000-000000000001',collaborator:'Ana',computer:'PC-01',label:'Design 01',sector:'Design'};
const user={id:'20000000-0000-4000-8000-000000000001'};
function record(extra={}){return {event_id:crypto.randomUUID(),kind:'uso',payload:{Horario:new Date().toISOString(),Aplicativo:'Corel.exe',Estado:'ativo',Segundos:'5',...extra}};}
function mock({allowed=true,paired=true,revoked=false,confirmed=false,claim=false}={}){
 const calls=[];const send=async(url,opts={})=>{calls.push([url,opts]);let value=[];
 if(url.endsWith('/auth/v1/user'))return Response.json({...user,email:'gestor@example.com',email_confirmed_at:confirmed?new Date().toISOString():null},{status:opts.headers.Authorization==='Bearer manager'?200:401});
 if(url.includes('mm_managers?'))value=allowed?[{user_id:user.id}]:[];
 else if(url.includes('mm_devices?token_hash'))value=revoked?[]:[device];
 else if(url.endsWith('rpc/mm_pair'))value=paired?device:null;
 else if(url.endsWith('rpc/mm_ingest')){const b=JSON.parse(opts.body);value={inserted:b.p_records.length,acknowledged:b.p_records.length};}
 else if(url.endsWith('rpc/mm_claim_manager'))value=claim;
 else if(url.endsWith('rpc/mm_report'))value={uso:[],raw_count:0};
 else if(url.includes('mm_devices?select='))value=[{id:device.id,label:device.label}];
 return Response.json(value);};return{send,calls};
}
function setup(options){const m=mock(options);return{...m,handle:createHandler({url:'https://test.supabase.co',serviceKey:'SERVER-ONLY',origin:'https://example.github.io'},m.send)};}
function req(route,{method='GET',token,body,origin='https://example.github.io'}={}){return new Request('https://test.supabase.co/functions/v1/monitor-api/'+route,{method,headers:{...(token?{Authorization:'Bearer '+token}:{}),'Content-Type':'application/json',Origin:origin},body:body===undefined?undefined:JSON.stringify(body)});}
test('hash e segredos usam 256 bits; normalizacao ignora identidade fornecida pela maquina',async()=>{
 const token=secret('mmdev_');assert.match(token,/^mmdev_[a-f0-9]{64}$/);assert.equal((await hash(token)).length,64);
 const r=normalizeRecords([record({Colaborador:'OUTRA PESSOA',Computador:'OUTRA MAQUINA'})],device)[0];assert.equal(r.payload.Colaborador,'Ana');assert.equal(r.payload.Computador,'PC-01');
 assert.throws(()=>normalizeRecords([record({Segundos:'NaN'})],device));assert.throws(()=>normalizeRecords([record({Estado:'produtivo'})],device));assert.throws(()=>normalizeRecords([record({Horario:'invalido'})],device));
 assert.equal(normalizeRecords([{...record(),kind:'desempenho',payload:{Horario:new Date().toISOString(),CPU:'',RAM:'95.5',Disco:'0',DiscoLivreGB:'0'}}],device)[0].payload.DiscoLivreGB,'0');
});
test('sem login, token de maquina ou usuario nao autorizado nao acessam o painel',async()=>{
 let{handle}=setup();assert.equal((await handle(req('devices'))).status,401);assert.equal((await handle(req('devices',{token:secret('mmdev_')}))).status,401);
 ({handle}=setup({allowed:false}));assert.equal((await handle(req('devices',{token:'manager'}))).status,403);
});
test('vinculo e de uso unico e nunca devolve a chave administrativa',async()=>{
 const {handle,calls}=setup();const response=await handle(req('pair',{method:'POST',body:{code:secret('mmpair_'),computer:'PC-01'}}));assert.equal(response.status,200);const answer=await response.json();assert.match(answer.token,/^mmdev_/);assert(!JSON.stringify(answer).includes('SERVER-ONLY'));const rpc=JSON.parse(calls.find(c=>c[0].endsWith('rpc/mm_pair'))[1].body);assert(!rpc.p_token_hash.startsWith('mmdev_'));
 const fail=setup({paired:false});assert.equal((await fail.handle(req('pair',{method:'POST',body:{code:secret('mmpair_'),computer:'PC'}}))).status,401);
});
test('ingestao valida credencial, dispositivo, esquema e confirma registros',async()=>{
 const{handle,calls}=setup();const token=secret('mmdev_');const response=await handle(req('ingest',{method:'POST',token,body:{device_id:device.id,records:[record()]}}));assert.equal(response.status,200);assert.equal((await response.json()).acknowledged,1);
 assert.equal((await handle(req('ingest',{method:'POST',token,body:{device_id:crypto.randomUUID(),records:[]}}))).status,403);
 assert.equal((await handle(req('ingest',{method:'POST',token,body:{device_id:device.id,records:[record({Segundos:-5})]}}))).status,400);
 const bad=setup({revoked:true});assert.equal((await bad.handle(req('ingest',{method:'POST',token,body:{device_id:device.id,records:[]}}))).status,401);
 const body=JSON.parse(calls.find(c=>c[0].endsWith('rpc/mm_ingest'))[1].body);assert.equal(body.p_records[0].local_hour,new Date().getUTCHours());
});
test('gestor cadastra e revoga, mas respostas e lista nao expoem hashes',async()=>{
 const {handle,calls}=setup();const response=await handle(req('devices',{method:'POST',token:'manager',body:{label:'Design',collaborator:'Ana',sector:'Design'}}));assert.equal(response.status,201);const created=await response.json();assert.match(created.code,/^mmpair_/);const inserted=JSON.parse(calls.find(c=>c[0].endsWith('/mm_devices'))[1].body);assert(!inserted.pairing_hash.startsWith('mmpair_'));
 const listed=await handle(req('devices',{token:'manager'}));assert(!(await listed.text()).includes('token_hash'));
 assert.equal((await handle(req('revoke',{method:'POST',token:'manager',body:{device_id:device.id}}))).status,200);
});
test('periodo, tamanho e origem sao validados e respostas nao sao armazenaveis',async()=>{
 const {handle}=setup();assert.equal((await handle(req('report?from=2026-01-01&to=2026-03-01',{token:'manager'}))).status,400);
 const good=await handle(req('report?from=2026-01-01&to=2026-01-01',{token:'manager'}));assert.equal(good.status,200);assert.equal(good.headers.get('cache-control'),'no-store');
 assert.equal((await handle(req('devices',{token:'manager',origin:'https://evil.example'}))).status,403);
 const huge=new Request('https://test/functions/v1/monitor-api/pair',{method:'POST',headers:{'Content-Type':'application/json'},body:'x'.repeat(1_500_001)});assert.equal((await handle(huge)).status,413);
});

test('primeiro acesso exige e-mail confirmado e convite autorizado no servidor',async()=>{
 let env=setup({allowed:false,confirmed:false,claim:true});assert.equal((await env.handle(req('devices',{token:'manager'}))).status,403);assert(!env.calls.some(c=>c[0].endsWith('rpc/mm_claim_manager')));
 env=setup({allowed:false,confirmed:true,claim:false});assert.equal((await env.handle(req('devices',{token:'manager'}))).status,403);
 env=setup({allowed:false,confirmed:true,claim:true});assert.equal((await env.handle(req('devices',{token:'manager'}))).status,200);
});
