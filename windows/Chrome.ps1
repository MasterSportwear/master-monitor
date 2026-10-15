# Somente o dominio da aba ativa, recebido da extensao pelo Native Messaging.
function Get-MMChromeDomain {
    param([string]$Root,[datetime]$Now=(Get-Date))
    $dir=Join-Path $Root 'chrome-snapshots'
    $focused=@()
    foreach($f in @(Get-ChildItem $dir -Filter '*.json' -ErrorAction SilentlyContinue)) {
        try {
            if($f.Length -gt 4096){continue}
            $s=Get-Content $f.FullName -Raw -Encoding UTF8|ConvertFrom-Json
            $age=([datetimeoffset]$Now-[datetimeoffset]$s.received_at).TotalSeconds
            if($age -lt 0 -or $age -gt 20 -or $s.focused -ne $true){continue}
            $focused+=,$s
        }catch{}
    }
    # Dois perfis ainda indicam foco durante uma troca: nao atribuir um dominio incerto.
    if($focused.Count -ne 1){return ''}
    $domain=[string]$focused[0].domain
    if($domain.Length -gt 253 -or $domain -notmatch '^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*$'){return ''}
    return $domain
}
function Install-MMChrome {
    param([string]$App)
    $hostExe=Join-Path $App 'ChromeHost.exe'
    if(Test-Path $hostExe){Remove-Item -LiteralPath $hostExe -Force}
    Add-Type -TypeDefinition (Get-Content (Join-Path $App 'ChromeHost.cs') -Raw -Encoding UTF8) -ReferencedAssemblies 'System.Runtime.Serialization.dll','System.Xml.dll' -OutputAssembly $hostExe -OutputType ConsoleApplication
    $manifest=@{name='com.mastersportwear.monitor';description='Master Monitor - dominios da aba ativa';path=$hostExe;type='stdio';allowed_origins=@('chrome-extension://plpmfkajjofibilaepninklkfbfedogm/')}
    $path=Join-Path $App 'chrome-host.json'
    [IO.File]::WriteAllText($path,($manifest|ConvertTo-Json -Depth 4),(New-Object Text.UTF8Encoding($false)))
    $reg='HKCU:\Software\Google\Chrome\NativeMessagingHosts\com.mastersportwear.monitor'
    New-Item -Path $reg -Force|Out-Null
    Set-Item -Path $reg -Value $path
}
