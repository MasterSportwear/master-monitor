// Native Messaging: somente snapshots locais de dominio; sem credenciais nem acesso a paginas.
using System;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Diagnostics;
[DataContract] public class MMChromeMessage {
 [DataMember(Name="protocol")] public string Protocol;
 [DataMember(Name="domain")] public string Domain;
 [DataMember(Name="enabled")] public bool Enabled;
 [DataMember(Name="focused")] public bool Focused;
}
[DataContract] public class MMChromeSnapshot {
 [DataMember(Name="domain")] public string Domain;
 [DataMember(Name="focused")] public bool Focused;
 [DataMember(Name="received_at")] public string ReceivedAt;
}
public static class MMChromeHost {
 public const string Origin="chrome-extension://plpmfkajjofibilaepninklkfbfedogm/";
 static bool ReadExact(Stream input,byte[] bytes) {
  int n=0;while(n<bytes.Length){int r=input.Read(bytes,n,bytes.Length-n);if(r==0)return false;n+=r;}return true;
 }
 static bool ValidDomain(string d) {
  if(d.Length==0)return true;if(d.Length>253||d.Contains(".."))return false;
  return Regex.IsMatch(d,@"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*$");
 }
 public static int Main(string[] args) {
  if(args.Length==0||args[0]!=Origin)return 1;
  string dir=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"MasterMonitor","chrome-snapshots");
  string file=Path.Combine(dir,Process.GetCurrentProcess().Id+".json"),tmp=file+".tmp";
  Stream input=Console.OpenStandardInput(),output=Console.OpenStandardOutput();
  try {
   Directory.CreateDirectory(dir);byte[] header=new byte[4];
   while(ReadExact(input,header)) {
    uint length=BitConverter.ToUInt32(header,0);if(length==0||length>4096)return 2;
    byte[] bytes=new byte[length];if(!ReadExact(input,bytes))return 2;
    MMChromeMessage m;
    using(var stream=new MemoryStream(bytes))m=(MMChromeMessage)new DataContractJsonSerializer(typeof(MMChromeMessage)).ReadObject(stream);
    string domain=(m.Domain??"").ToLowerInvariant();
    if(m.Protocol!="mm-domain-v1"||!ValidDomain(domain))return 3;
    if(!m.Enabled){if(File.Exists(file))File.Delete(file);}
    else {
     var snapshot=new MMChromeSnapshot{Domain=m.Focused?domain:"",Focused=m.Focused,ReceivedAt=DateTime.UtcNow.ToString("o")};
     using(var stream=new FileStream(tmp,FileMode.Create,FileAccess.Write,FileShare.None))new DataContractJsonSerializer(typeof(MMChromeSnapshot)).WriteObject(stream,snapshot);
     if(File.Exists(file))File.Replace(tmp,file,null);else File.Move(tmp,file);
    }
    byte[] ack=Encoding.UTF8.GetBytes("{\"ok\":true}");output.Write(BitConverter.GetBytes(ack.Length),0,4);output.Write(ack,0,ack.Length);output.Flush();
   }return 0;
  }catch{return 4;}
  finally{try{if(File.Exists(file))File.Delete(file);if(File.Exists(tmp))File.Delete(tmp);}catch{}}
 }
}
