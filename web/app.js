'use strict';
(() => {
 // A confirmacao de e-mail pode retornar tokens no fragmento. Nao os manter no endereco.
 if(/(?:access_token|refresh_token)=/.test(location.hash))history.replaceState(null,'',location.pathname+location.search);
 const cfg=window.MM_CONFIG||{},storageKey='mm-manager-session-v2';let session=null,pairing=null,busy=false,deviceCache=[],generation=0;
 const apiUrl=String(cfg.supabaseUrl||'').replace(/\/$/,'')+'/functions/v1/monitor-api';
 function validateConfig(){
  if(!/^https:\/\/[a-z0-9-]+\.supabase\.co$/.test(cfg.supabaseUrl||''))throw Error('O projeto Supabase ainda precisa ser configurado para este painel.');
  if(!cfg.publishableKey||String(cfg.publishableKey).startsWith('sb_secret_'))throw Error('Chave publica ausente ou invalida.');
  if(String(cfg.publishableKey).startsWith('eyJ')){try{const p=JSON.parse(atob(cfg.publishableKey.split('.')[1].replace(/-/g,'+').replace(/_/g,'/')));if(p.role!=='anon')throw Error('Chave administrativa proibida no painel.');}catch(e){throw Error('Use apenas uma chave publica publishable ou anon.');}}
 }
 function localDay(){const d=new Date();return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0');}
 function saveSession(s){session=s;if(s)sessionStorage.setItem(storageKey,JSON.stringify(s));else sessionStorage.removeItem(storageKey);}
 async function auth(body,grant){validateConfig();const r=await fetch(cfg.supabaseUrl+'/auth/v1/token?grant_type='+grant,{method:'POST',headers:{apikey:cfg.publishableKey,'Content-Type':'application/json'},body:JSON.stringify(body)});const d=await r.json();if(!r.ok){const e=Error(grant==='password'?'E-mail ou senha invalidos, ou acesso ainda nao confirmado.':'Sessao expirada. Entre novamente.');e.status=grant==='password'?400:401;throw e;}saveSession({...d,expires_at:Math.floor(Date.now()/1000)+(d.expires_in||3600)});return d;}
 async function api(route,{method='GET',body,retry=true}={}){
  if(!session)throw Error('Entre com seu login.');if(session.expires_at*1000<Date.now()+60000)await auth({refresh_token:session.refresh_token},'refresh_token');
  const response=await fetch(apiUrl+'/'+route,{method,headers:{Authorization:'Bearer '+session.access_token,'Content-Type':'application/json'},body:body===undefined?undefined:JSON.stringify(body)});
  if(response.status===401&&retry){await auth({refresh_token:session.refresh_token},'refresh_token');return api(route,{method,body,retry:false});}
  const value=await response.json();if(!response.ok){const e=Error(value.error||'Falha ao consultar o servidor.');e.status=response.status;throw e;}return value;
 }
 function clean(){data={uso:[],desempenho:[],eventos:[],operacao:[]};keys.clear();filters();render();$('device-list').replaceChildren();$('status').textContent='';$('report-error').textContent='';pairing=null;deviceCache=[];$('pair-output').textContent='';$('pair-result').hidden=true;}
 function logout(message=''){generation++;saveSession(null);clean();$('dashboard-view').hidden=true;$('login-view').hidden=false;$('password').value='';$('login-error').textContent=message;}
 function when(v){return v?new Date(v).toLocaleString('pt-BR'):'—';}
 function renderDevices(){
  const now=Date.now();table('device-list',deviceCache,[['Máquina',r=>r.label],['Colaborador','collaborator'],['Setor','sector'],['Computador Windows',r=>r.computer||'Ainda não vinculado'],['Situação',r=>r.revoked_at?'Revogada':!r.computer?'Aguardando vínculo':r.last_seen_at&&now-Date.parse(r.last_seen_at)<12*60000?'Comunicação recente':'Sem comunicação recente'],['Última comunicação',r=>when(r.last_seen_at)],['Última amostra',r=>when(r.last_sample_at)],['Ação',r=>'']]);
  $('device-list').querySelectorAll('tbody tr').forEach((tr,i)=>{const d=deviceCache[i];if(!d.revoked_at){const button=document.createElement('button');button.textContent='Revogar';button.className='secondary';button.addEventListener('click',async()=>{if(!confirm('Revogar os novos envios de '+d.label+'? O histórico será preservado.'))return;button.disabled=true;try{await api('revoke',{method:'POST',body:{device_id:d.id}});await load();}catch(e){$('report-error').textContent=e.message;button.disabled=false;}});tr.lastElementChild.append(button);}});
 }
 async function load(){
  if(busy||!session)return;busy=true;const run=generation;$('refresh').disabled=true;$('status').textContent='Carregando dados…';$('report-error').textContent='';
  const from=$('from').value,to=$('to').value;
  try{
   if(!from||!to||to<from||(Date.parse(to)-Date.parse(from))/86400000>30)throw Error('Selecione um período válido de até 31 dias.');
   const[d,r]=await Promise.all([api('devices'),api('report?from='+encodeURIComponent(from)+'&to='+encodeURIComponent(to))]);
   if(run!==generation||!session)return;
   deviceCache=d.devices||[];renderDevices();data={uso:r.uso||[],desempenho:r.desempenho||[],eventos:r.eventos||[],operacao:r.operacao||[]};filters();render();
   let label='Atualizado às '+new Date().toLocaleTimeString('pt-BR')+' · '+r.raw_count.toLocaleString('pt-BR')+' registros no período';
   if(r.eventos_total>1000||r.operacao_total>1000)label+=' · LISTAS LIMITADAS: '+r.eventos_total+' eventos e '+r.operacao_total+' registros de operação. Reduza o período.';
   $('status').textContent=label;
  }catch(e){if(run!==generation)return;if(e.status===401||e.status===403)logout(e.message);else{$('report-error').textContent=e.message;$('status').textContent='Não foi possível atualizar. Os dados exibidos podem estar desatualizados.';}}
  finally{busy=false;$('refresh').disabled=false;}
 }
 async function showDashboard(){
  $('from').value=localDay();$('to').value=localDay();await api('devices');$('login-view').hidden=true;$('dashboard-view').hidden=false;await load();
 }
 $('login-form').addEventListener('submit',async e=>{e.preventDefault();$('login-button').disabled=true;$('login-error').textContent='';try{await auth({email:$('email').value.trim(),password:$('password').value},'password');$('password').value='';await showDashboard();}catch(err){logout(err.message);}finally{$('login-button').disabled=false;}});
 $('first-access').addEventListener('click',async()=>{
  $('login-error').textContent='';$('login-info').textContent='';
  try{validateConfig();const email=$('email').value.trim(),password=$('password').value;if(!email||password.length<12)throw Error('Preencha e-mail e uma senha de pelo menos 12 caracteres para o primeiro acesso.');
   $('first-access').disabled=true;
   const res=await fetch(cfg.supabaseUrl+'/auth/v1/signup?redirect_to='+encodeURIComponent(location.href.split('#')[0]),{method:'POST',headers:{apikey:cfg.publishableKey,'Content-Type':'application/json'},body:JSON.stringify({email,password})});
   const result=await res.json();if(!res.ok)throw Error('Nao foi possivel criar o acesso. Verifique o e-mail, a politica de senha ou tente mais tarde.');
   $('password').value='';$('login-info').textContent='Se o cadastro foi aceito, confirme o e-mail enviado pelo Supabase e volte para entrar. Apenas o e-mail autorizado na implantacao recebe acesso de gestor.';
  }catch(e){$('login-error').textContent=e.message;}finally{$('first-access').disabled=false;}
 });
 $('logout').addEventListener('click',()=>{const token=session?.access_token;logout();if(token)fetch(cfg.supabaseUrl+'/auth/v1/logout',{method:'POST',headers:{apikey:cfg.publishableKey,Authorization:'Bearer '+token}}).catch(()=>{});});
 $('refresh').addEventListener('click',load);$('load-period').addEventListener('click',load);$('print').addEventListener('click',()=>window.print());for(const id of['day','person','machine','sector'])$(id).addEventListener('change',render);
 $('new-device').addEventListener('click',()=>{$('device-form').reset();$('device-form').hidden=false;$('pair-result').hidden=true;$('device-error').textContent='';pairing=null;$('device-dialog').showModal();});
 for(const id of['close-device','close-pair'])$(id).addEventListener('click',()=>{$('device-dialog').close();pairing=null;$('pair-output').textContent='';});
 $('device-form').addEventListener('submit',async e=>{e.preventDefault();$('create-device').disabled=true;$('device-error').textContent='';try{const result=await api('devices',{method:'POST',body:{label:$('device-label').value.trim(),collaborator:$('device-person').value.trim(),sector:$('device-sector').value.trim()}});pairing={api_url:apiUrl,code:result.code};$('device-form').hidden=true;$('pair-result').hidden=false;$('pair-output').textContent='Cadastro: '+$('device-label').value+'\nExpira em: '+when(result.expires_at)+'\nCódigo de uso único protegido no arquivo de vínculo.';await load();}catch(err){$('device-error').textContent=err.message;}finally{$('create-device').disabled=false;}});
 $('download-pair').addEventListener('click',()=>{if(!pairing)return;const url=URL.createObjectURL(new Blob([JSON.stringify(pairing,null,2)],{type:'application/json'})),a=document.createElement('a');a.href=url;a.download='vinculo.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);});
 document.addEventListener('visibilitychange',()=>{if(!document.hidden&&session)load();});setInterval(()=>{if(!document.hidden&&session)load();},60000);
 filters();render();
 try{validateConfig();const stored=sessionStorage.getItem(storageKey);if(stored){session=JSON.parse(stored);showDashboard().catch(e=>logout(e.message));}}catch(e){logout(e.message);}
})();
