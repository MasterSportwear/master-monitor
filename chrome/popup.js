const button=document.getElementById('toggle'),status=document.getElementById('status');let enabled=false;
function render(){status.textContent=enabled?'Coleta de domínios ativada neste perfil. Confira o indicador Chrome na janela do monitor.':'Coleta de domínios desativada.';button.textContent=enabled?'Desativar coleta de domínios':'Li o aviso: ativar coleta de domínios';button.disabled=false;}
chrome.storage.local.get({enabled:false}).then(s=>{enabled=s.enabled===true;render();});
button.addEventListener('click',async()=>{button.disabled=true;try{await chrome.storage.local.set({enabled:!enabled});enabled=!enabled;render();}catch{status.textContent='Não foi possível salvar a preferência. Tente novamente.';button.disabled=false;}});
