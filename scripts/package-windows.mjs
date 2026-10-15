import {readFile,writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {deflateRawSync} from 'node:zlib';
// Lista fechada: nunca empacotar dados, vinculos ou credenciais locais.
const names=['INSTALAR.cmd','Instalar.ps1','INICIAR.cmd','DESINSTALAR.cmd','Desinstalar.ps1','Monitor.ps1','Core.ps1','Queue.ps1','Sync.ps1','PAINEL.html','LEIA-ME.html','COMECE-AQUI.txt'];
function crc32(bytes){let crc=0xffffffff;for(const byte of bytes){crc^=byte;for(let k=0;k<8;k++)crc=(crc>>>1)^((crc&1)?0xedb88320:0);}return (crc^0xffffffff)>>>0;}
export async function packageWindows(root,destination){
 const locals=[],centrals=[];let offset=0;
 for(const filename of names){
  const name=Buffer.from(filename),raw=await readFile(join(root,'windows',filename)),packed=deflateRawSync(raw),crc=crc32(raw);
  const local=Buffer.alloc(30);local.writeUInt32LE(0x04034b50,0);local.writeUInt16LE(20,4);local.writeUInt16LE(0x0800,6);local.writeUInt16LE(8,8);local.writeUInt16LE(((2026-1980)<<9)|(10<<5)|15,12);local.writeUInt32LE(crc,14);local.writeUInt32LE(packed.length,18);local.writeUInt32LE(raw.length,22);local.writeUInt16LE(name.length,26);
  locals.push(local,name,packed);
  const central=Buffer.alloc(46);central.writeUInt32LE(0x02014b50,0);central.writeUInt16LE(20,4);central.writeUInt16LE(20,6);central.writeUInt16LE(0x0800,8);central.writeUInt16LE(8,10);central.writeUInt16LE(((2026-1980)<<9)|(10<<5)|15,14);central.writeUInt32LE(crc,16);central.writeUInt32LE(packed.length,20);central.writeUInt32LE(raw.length,24);central.writeUInt16LE(name.length,28);central.writeUInt32LE(offset,42);
  centrals.push(central,name);offset+=local.length+name.length+packed.length;
 }
 const directory=Buffer.concat(centrals),end=Buffer.alloc(22);end.writeUInt32LE(0x06054b50,0);end.writeUInt16LE(names.length,8);end.writeUInt16LE(names.length,10);end.writeUInt32LE(directory.length,12);end.writeUInt32LE(offset,16);
 await writeFile(destination,Buffer.concat([...locals,directory,end]));return names.length;
}
