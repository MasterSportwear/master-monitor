import{createTracker}from'./tracker.js';
const tracker=createTracker(chrome);
chrome.tabs.onActivated.addListener(()=>void tracker.sample());
chrome.tabs.onUpdated.addListener(()=>void tracker.sample());
chrome.tabs.onRemoved.addListener(()=>void tracker.sample());
chrome.windows.onFocusChanged.addListener(()=>void tracker.sample());
chrome.storage.onChanged.addListener((changes,area)=>{if(area==='local'&&changes.enabled)void tracker.consent(changes.enabled.newValue);});
chrome.runtime.onInstalled.addListener(()=>chrome.tabs.create({url:chrome.runtime.getURL('popup.html')}));
chrome.storage.local.get({enabled:false}).then(s=>tracker.consent(s.enabled));
// A conexão nativa mantém o service worker ativo. O pulso renova apenas a amostra atual.
setInterval(()=>void tracker.sample(),10000);
