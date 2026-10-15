import test from'node:test';import assert from'node:assert/strict';import{spawn,execFileSync}from'node:child_process';import{mkdtempSync,writeFileSync,readFileSync,existsSync,rmSync}from'node:fs';import{tmpdir}from'node:os';import{resolve,join}from'node:path';import{once}from'node:events';
const windows=process.platform==='win32',pwsh=windows?'powershell.exe':process.env.MM_PWSH;
test('Native host: framing binario, hostname apenas, origem restrita e limpeza', {skip:!pwsh,timeout:40000},async()=>{
 const tmp=mkdtempSync(join(tmpdir(),'mm-native-')),source=resolve('windows/ChromeHost.cs');let child;
 try{
  const script=join(tmp,'compile.ps1'),exe=join(tmp,'ChromeHost.exe');
  writeFileSync(script,`$ErrorActionPreference='Stop'\n`+(windows?`Add-Type -TypeDefinition (Get-Content -LiteralPath '${source.replaceAll("'","''")}' -Raw) -ReferencedAssemblies 'System.Runtime.Serialization.dll','System.Xml.dll' -OutputAssembly '${exe.replaceAll("'","''")}' -OutputType ConsoleApplication`:`Add-Type -TypeDefinition (Get-Content -LiteralPath '${source}' -Raw)\nexit [MMChromeHost]::Main(@($args[0]))`));
  if(windows)execFileSync(pwsh,['-NoProfile','-File',script],{timeout:20000});
  const origin='chrome-extension://plpmfkajjofibilaepninklkfbfedogm/';
  child=windows?spawn(exe,[origin]):spawn(pwsh,['-NoProfile','-File',script,origin]);
  const root=execFileSync(pwsh,['-NoProfile','-Command',"[Environment]::GetFolderPath('LocalApplicationData')"],{encoding:'utf8'}).trim();const snapshot=join(root,'MasterMonitor','chrome-snapshots',child.pid+'.json');
  let output=Buffer.alloc(0);child.stdout.on('data',d=>output=Buffer.concat([output,d]));let err='';child.stderr.on('data',d=>err+=d);
  async function send(domain,enabled=true){const data=Buffer.from(JSON.stringify({protocol:'mm-domain-v1',domain,focused:true,enabled})),h=Buffer.alloc(4);h.writeUInt32LE(data.length);const before=output.length;child.stdin.write(Buffer.concat([h,data]));const deadline=Date.now()+10000;while(output.length<before+15&&Date.now()<deadline)await new Promise(r=>setTimeout(r,15));assert.equal(output.subarray(before+4).toString(),'{"ok":true}',err);assert.equal(output.readUInt32LE(before),11);}
  await send('drive.google.com');const record=JSON.parse(readFileSync(snapshot,'utf8'));assert.equal(record.domain,'drive.google.com');assert(record.focused);assert(!JSON.stringify(record).includes('http'));
  await send('accounts.google.com');assert.equal(JSON.parse(readFileSync(snapshot,'utf8')).domain,'accounts.google.com');
  await send('',false);assert(!existsSync(snapshot));
  await send('drive.google.com');child.stdin.end();const[code]=await once(child,'exit');assert.equal(code,0,err);assert(!existsSync(snapshot));
  const denied=windows?spawn(exe,['chrome-extension://wrong/']):spawn(pwsh,['-NoProfile','-File',script,'chrome-extension://wrong/']);assert.equal((await once(denied,'exit'))[0],1);
 }finally{child?.kill();rmSync(tmp,{recursive:true,force:true});}
});
