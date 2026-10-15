export function domainOf(tab){
 if(!tab||tab.incognito||tab.status==='loading')return '';
 try{const u=new URL(tab.url);if(!['https:','http:'].includes(u.protocol))return '';const d=u.hostname.toLowerCase().replace(/\.$/,'');return d.length<=253&&/^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$/.test(d)?d:'';}catch{return '';}
}
export function createTracker(api){
 let port=null,enabled=false,busy=false,again=false,revision=0;
 function badge(text,title){api.action.setBadgeText({text});api.action.setTitle({title});}
 function disconnect(){if(port){const p=port;port=null;p.disconnect();}}
 async function sample(){
  if(busy){again=true;revision++;return;}busy=true;const run=revision;
  try{
   if(!enabled)return;
   if(!port){
    const p=api.runtime.connectNative('com.mastersportwear.monitor');port=p;
    p.onDisconnect.addListener(()=>{void api.runtime.lastError;if(port===p){port=null;badge('!', 'Master Monitor: integração local indisponível. Atualize o monitor.');}});
    p.onMessage.addListener(m=>{if(enabled&&port===p)badge(m.ok?'ON':'!',m.ok?'Master Monitor: coleta de domínios ativada':'Master Monitor: falha na integração local');});
   }
   const w=await api.windows.getLastFocused({windowTypes:['normal']});
   const tabs=w?.focused&&!w.incognito?await api.tabs.query({active:true,windowId:w.id}):[];
   if(!enabled||run!==revision)return;
   const domain=w?.focused?domainOf(tabs[0]):'';
   port?.postMessage({protocol:'mm-domain-v1',enabled:true,focused:Boolean(w?.focused),domain});
  }catch{disconnect();badge('!', 'Master Monitor: integração local indisponível.');}
  finally{busy=false;if(again){again=false;void sample();}}
 }
 async function consent(value){
  revision++;enabled=value===true;
  if(!enabled){try{port?.postMessage({protocol:'mm-domain-v1',enabled:false,focused:false,domain:''});}catch{}disconnect();badge('OFF','Master Monitor: coleta de domínios desativada');}
  else await sample();
 }
 return{sample,consent};
}
