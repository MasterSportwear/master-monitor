import {cp,mkdir,readFile,writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
const root=resolve(import.meta.dirname,'..'),out=resolve(root,'dist');
await mkdir(out,{recursive:true});await cp(resolve(root,'web'),out,{recursive:true});
const url=process.env.MM_SUPABASE_URL,key=process.env.MM_PUBLISHABLE_KEY;
if(url||key){
 if(!/^https:\/\/[a-z0-9-]+\.supabase\.co$/.test(url||''))throw Error('MM_SUPABASE_URL invalida');
 if(!key||key.startsWith('sb_secret_'))throw Error('Use apenas chave publica');
 if(key.startsWith('eyJ')){const payload=JSON.parse(Buffer.from(key.split('.')[1],'base64url'));if(payload.role!=='anon')throw Error('Chave administrativa proibida');}
 await writeFile(resolve(out,'config.js'),'window.MM_CONFIG = Object.freeze('+JSON.stringify({supabaseUrl:url,publishableKey:key})+');\n');
}
await writeFile(resolve(out,'.nojekyll'),'');
console.log('Painel preparado em dist/. Configuracao publica '+(url?'incluida.':'ainda pendente.'));
