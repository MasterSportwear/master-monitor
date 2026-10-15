import test from 'node:test';import assert from'node:assert/strict';import{domainOf,createTracker}from'../chrome/tracker.js';
test('Chrome: reduz URLs a hostname e ignora anonimo, internas e carregamento',()=>{
 assert.equal(domainOf({url:'https://drive.google.com/secret/document?token=private#private',status:'complete'}),'drive.google.com');
 for(const tab of[{url:'chrome://settings/'},{url:'file:///secret'},{url:'https://example.com',incognito:true},{url:'https://example.com',status:'loading'},{url:'invalid'}])assert.equal(domainOf(tab),'');
});
function fake(){const messages=[],listeners={};let focused=true,tab={url:'https://drive.google.com/a-secret?key=SECRET',status:'complete'},connections=0;const api={action:{setBadgeText(){},setTitle(){}},runtime:{connectNative(){connections++;return{onDisconnect:{addListener:f=>listeners.disconnect=f},onMessage:{addListener:f=>listeners.message=f},postMessage:m=>messages.push(m),disconnect(){}}}},windows:{async getLastFocused(){return{id:1,focused}}},tabs:{async query(){return[tab]}}};return{api,messages,get connections(){return connections},setFocused:v=>focused=v,setTab:v=>tab=v};}
test('Chrome: exige ativacao, transmite so hostname e limpa foco ou desativacao',async()=>{
 const f=fake(),tracker=createTracker(f.api);await tracker.sample();assert.equal(f.connections,0);
 await tracker.consent(true);assert.equal(f.connections,1);assert.deepEqual(f.messages[0],{protocol:'mm-domain-v1',enabled:true,focused:true,domain:'drive.google.com'});assert(!JSON.stringify(f.messages).includes('SECRET'));
 f.setFocused(false);await tracker.sample();assert.equal(f.messages.at(-1).domain,'');assert.equal(f.messages.at(-1).focused,false);
 f.setFocused(true);f.setTab({url:'chrome://newtab/'});await tracker.sample();assert.equal(f.messages.at(-1).domain,'');
 await tracker.consent(false);assert.equal(f.messages.at(-1).enabled,false);const n=f.messages.length;await tracker.sample();assert.equal(f.messages.length,n);
});
test('Chrome: foco incerto e acesso bloqueado nao reutilizam dominio anterior',async()=>{
 const f=fake(),tracker=createTracker(f.api);await tracker.consent(true);f.api.windows.getLastFocused=async()=>{throw Error('closed')};await tracker.sample();assert.equal(f.messages.length,1);
});
