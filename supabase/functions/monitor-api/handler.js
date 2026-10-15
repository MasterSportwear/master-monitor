const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const KINDS=new Set(['uso','desempenho','eventos','operacao']);
export class ApiError extends Error { constructor(status,message){super(message);this.status=status;} }
export async function hash(value){return [...new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value)))].map(x=>x.toString(16).padStart(2,'0')).join('');}
export function secret(prefix){const b=new Uint8Array(32);crypto.getRandomValues(b);return prefix+[...b].map(x=>x.toString(16).padStart(2,'0')).join('');}
function text(value,max=100){if(typeof value!=='string'||!value.trim()||value.length>max)throw new ApiError(400,'Campo de texto invalido.');return value.trim();}
export function normalizeRecords(records,device){
 if(!Array.isArray(records)||records.length>500)throw new ApiError(400,'Lote invalido: maximo de 500 registros.');
 return records.map(r=>{
  if(!r||!UUID.test(r.event_id)||!KINDS.has(r.kind)||!r.payload||typeof r.payload!=='object'||Array.isArray(r.payload))throw new ApiError(400,'Registro invalido.');
  const stamp=r.payload.Horario;
  if(typeof stamp!=='string'||!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/.test(stamp)||!Number.isFinite(Date.parse(stamp)))throw new ApiError(400,'Horario invalido.');
  if(Date.parse(stamp)>Date.now()+86400000||Date.parse(stamp)<Date.UTC(2020,0,1))throw new ApiError(400,'Confira o relogio do computador.');
  const p={Horario:stamp,Colaborador:device.collaborator,Setor:device.sector,Computador:device.computer||device.label};
  const number=(v,min,max,optional=false)=>{if(optional&&(v===''||v===null||v===undefined))return '';const n=Number(v);if(v===''||v===null||v===undefined||!Number.isFinite(n)||n<min||n>max)throw new ApiError(400,'Indicador numerico invalido.');return String(n);};
  if(r.kind==='uso'){
   if(!['ativo','inativo','sem janela','sessao indisponivel'].includes(r.payload.Estado))throw new ApiError(400,'Estado invalido.');
   Object.assign(p,{Aplicativo:text(r.payload.Aplicativo,260),Estado:r.payload.Estado,Segundos:number(r.payload.Segundos,0,180)});
  }else if(r.kind==='desempenho'){
   for(const k of ['CPU','RAM','Disco'])p[k]=number(r.payload[k],0,100,true);p.DiscoLivreGB=number(r.payload.DiscoLivreGB,0,1e9,true);
  }else{
   p.Tipo=text(r.payload.Tipo,150);p.Detalhe=String(r.payload.Detalhe??'').slice(0,3000);
   if(r.kind==='eventos'){p.Origem=text(r.payload.Origem,200);p.ID=number(r.payload.ID,0,2147483647);p.Escopo='Sistema inteiro';p.Chave=String(r.payload.Chave??'').slice(0,300);}
  }
  return{event_id:r.event_id,kind:r.kind,captured_at:stamp,local_day:stamp.slice(0,10),local_hour:Number(stamp.slice(11,13)),payload:p};
 });
}
export function createHandler(config,fetchImpl=fetch){
 const {url,serviceKey}=config;
 const cors=(req)=>({'Access-Control-Allow-Origin':config.origin||req.headers.get('Origin')||'*','Vary':'Origin','Access-Control-Allow-Headers':'authorization,content-type','Access-Control-Allow-Methods':'GET,POST,OPTIONS','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});
 async function db(path,{method='GET',body,prefer}={}){
  const res=await fetchImpl(url+'/rest/v1/'+path,{method,headers:{apikey:serviceKey,Authorization:'Bearer '+serviceKey,'Content-Type':'application/json',...(prefer?{Prefer:prefer}:{})},body:body===undefined?undefined:JSON.stringify(body)});
  if(!res.ok){console.error('Database operation failed',res.status);throw new ApiError(503,'Banco temporariamente indisponivel.');}
  if(res.status===204)return null;const raw=await res.text();return raw?JSON.parse(raw):null;
 }
 async function manager(req){
  const token=(req.headers.get('authorization')||'').replace(/^Bearer /i,'');if(!token||token.startsWith('mmdev_'))throw new ApiError(401,'Entre com seu login.');
  const res=await fetchImpl(url+'/auth/v1/user',{headers:{apikey:serviceKey,Authorization:'Bearer '+token}});
  if(!res.ok)throw new ApiError(401,'Sessao expirada. Entre novamente.');const user=await res.json();if(!UUID.test(user.id))throw new ApiError(401,'Usuario invalido.');
  const allowed=await db('mm_managers?user_id=eq.'+user.id+'&enabled=eq.true&select=user_id');
  if(!allowed?.length){
   let claimed=false;
   if(user.email_confirmed_at&&typeof user.email==='string')claimed=await db('rpc/mm_claim_manager',{method:'POST',body:{p_user:user.id,p_email:user.email}});
   if(claimed!==true)throw new ApiError(403,'Este usuario nao possui acesso de gestor.');
  }return user;
 }
 async function body(req){
  if(Number(req.headers.get('content-length')||0)>1_500_000)throw new ApiError(413,'Requisicao muito grande.');
  if(!req.headers.get('content-type')?.includes('application/json'))throw new ApiError(415,'Use JSON.');
  // Limite tambem aplicado a transmissoes sem Content-Length.
  const reader=req.body?.getReader();if(!reader)throw new ApiError(400,'Corpo ausente.');let size=0;const chunks=[];
  while(true){const part=await reader.read();if(part.done)break;size+=part.value.byteLength;if(size>1_500_000){await reader.cancel();throw new ApiError(413,'Requisicao muito grande.');}chunks.push(part.value);}
  const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}try{return JSON.parse(new TextDecoder().decode(bytes));}catch{throw new ApiError(400,'JSON invalido.');}
 }
 return async(req)=>{
  const headers=cors(req),reply=(value,status=200)=>new Response(JSON.stringify(value),{status,headers:{...headers,'Content-Type':'application/json; charset=utf-8'}});
  if(config.origin&&req.headers.get('Origin')&&req.headers.get('Origin')!==config.origin)return reply({error:'Origem nao autorizada.'},403);
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
  try{
   if(!url||!serviceKey)throw new ApiError(503,'Servidor ainda nao configurado.');
   const endpoint=new URL(req.url),route=endpoint.pathname.split('/').filter(Boolean).pop();
   if(req.method==='POST'&&route==='pair'){
    const p=await body(req),code=text(p.code,100),computer=text(p.computer,100);if(!/^mmpair_[a-f0-9]{64}$/.test(code))throw new ApiError(401,'Codigo de vinculacao invalido.');
    const token=secret('mmdev_'),device=await db('rpc/mm_pair',{method:'POST',body:{p_pair_hash:await hash(code),p_token_hash:await hash(token),p_computer:computer}});
    if(!device)throw new ApiError(401,'Codigo expirado ou ja utilizado.');return reply({device,token});
   }
   if(req.method==='POST'&&route==='ingest'){
    const token=(req.headers.get('authorization')||'').replace(/^Bearer /i,'');if(!/^mmdev_[a-f0-9]{64}$/.test(token))throw new ApiError(401,'Credencial de maquina invalida.');
    const found=await db('mm_devices?token_hash=eq.'+await hash(token)+'&revoked_at=is.null&select=id,collaborator,sector,computer,label');const device=found?.[0];if(!device)throw new ApiError(401,'Maquina nao vinculada ou revogada.');
    const p=await body(req);if(p.device_id!==device.id)throw new ApiError(403,'Credencial de outra maquina.');const rows=normalizeRecords(p.records,device);
    const result=await db('rpc/mm_ingest',{method:'POST',body:{p_device:device.id,p_records:rows}});return reply(result);
   }
   const user=await manager(req);
   if(req.method==='GET'&&route==='devices'){
    const devices=await db('mm_devices?select=id,label,collaborator,sector,computer,created_at,last_seen_at,last_sample_at,revoked_at,pairing_expires_at&order=created_at.desc&limit=1000');return reply({devices});
   }
   if(req.method==='POST'&&route==='devices'){
    const p=await body(req),code=secret('mmpair_'),id=crypto.randomUUID(),expires=new Date(Date.now()+86400000).toISOString();
    await db('mm_devices',{method:'POST',body:{id,label:text(p.label),collaborator:text(p.collaborator),sector:text(p.sector),created_by:user.id,pairing_hash:await hash(code),pairing_expires_at:expires}});
    return reply({device_id:id,code,expires_at:expires},201);
   }
   if(req.method==='POST'&&route==='revoke'){
    const p=await body(req);if(!UUID.test(p.device_id))throw new ApiError(400,'Maquina invalida.');await db('mm_devices?id=eq.'+p.device_id,{method:'PATCH',body:{revoked_at:new Date().toISOString(),token_hash:null,pairing_hash:null,pairing_expires_at:null}});return reply({ok:true});
   }
   if(req.method==='GET'&&route==='report'){
    const from=endpoint.searchParams.get('from'),to=endpoint.searchParams.get('to'),device=endpoint.searchParams.get('device')||null;
    if(!/^\d{4}-\d{2}-\d{2}$/.test(from||'')||!/^\d{4}-\d{2}-\d{2}$/.test(to||'')||!Number.isFinite(Date.parse(from))||!Number.isFinite(Date.parse(to))||Date.parse(to)<Date.parse(from)||(Date.parse(to)-Date.parse(from))/86400000>30||(device&&!UUID.test(device)))throw new ApiError(400,'Selecione um periodo de ate 31 dias.');
    const report=await db('rpc/mm_report',{method:'POST',body:{p_from:from,p_to:to,p_device:device}});return reply(report);
   }
   throw new ApiError(404,'Rota nao encontrada.');
  }catch(e){if(!(e instanceof ApiError))console.error('API failure',e?.name);return reply({error:e instanceof ApiError?e.message:'Falha interna. Tente novamente.'},e instanceof ApiError?e.status:500);}
 };
}
