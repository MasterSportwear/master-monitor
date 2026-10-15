#requires -Version 5.1
param([string]$Root=(Join-Path $env:LOCALAPPDATA 'MasterMonitor'))
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Queue.ps1')
$m=New-Object Threading.Mutex -ArgumentList @($false, ('Local\MasterMonitorSync-'+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
if (!$m.WaitOne(0)) { $m.Dispose();exit }
$sent=0;$status='error';$detail='';$lastSuccess=$null
try {
    $previous=Join-Path $Root 'sync-status.json'
    if(Test-Path $previous){try{$lastSuccess=(Get-Content $previous -Raw -Encoding UTF8|ConvertFrom-Json).last_success}catch{}}
    $cfg=Get-Content (Join-Path $Root 'cloud.json') -Raw -Encoding UTF8|ConvertFrom-Json
    if ($cfg.api_url -notmatch '^https://[a-z0-9-]+\.supabase\.co/functions/v1/monitor-api$') { throw 'Endereco do servidor invalido.' }
    $secure=ConvertTo-SecureString ([IO.File]::ReadAllText((Join-Path $Root 'device.key')))
    $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { $token=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    Rotate-MMQueue $Root
    $files=@(Get-ChildItem (Join-Path $Root 'fila') -Filter '*.jsonl' | Where-Object Name -ne 'active.jsonl' | Sort-Object Name)
    $clock=[Diagnostics.Stopwatch]::StartNew();$posted=$false
    foreach ($file in $files) {
        while ((Test-Path $file.FullName) -and $clock.Elapsed.TotalSeconds -lt 90) {
            $batch=@(Read-MMQueueBatch $file.FullName)
            if ($batch.Count -eq 0) { Remove-Item -LiteralPath $file.FullName;break }
            $body=@{device_id=$cfg.device_id;records=@($batch)}|ConvertTo-Json -Depth 8 -Compress
            $answer=Invoke-RestMethod -Uri ($cfg.api_url+'/ingest') -Method Post -Headers @{Authorization='Bearer '+$token} -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 20
            if ([int]$answer.acknowledged -ne $batch.Count) { throw 'Servidor nao confirmou todos os registros. O lote sera reenviado.' }
            Complete-MMQueueBatch $file.FullName $batch.Count
            $sent+=$batch.Count;$posted=$true;$lastSuccess=(Get-Date).ToString('o')
        }
        if ($clock.Elapsed.TotalSeconds -ge 90) { break }
    }
    if (!$posted) {
        $body=@{device_id=$cfg.device_id;records=@()}|ConvertTo-Json -Compress
        [void](Invoke-RestMethod -Uri ($cfg.api_url+'/ingest') -Method Post -Headers @{Authorization='Bearer '+$token} -ContentType 'application/json' -Body $body -TimeoutSec 20)
        $lastSuccess=(Get-Date).ToString('o')
    }
    $status='ok';$detail="$sent registros confirmados."
} catch {
    $detail='Envio pendente. Verifique internet, vinculacao e relogio; a fila foi preservada.'
    $http=$null
    try {$http=[int]$_.Exception.Response.StatusCode}catch{}
    if ($http -eq 401 -or $http -eq 403) { $detail='Credencial revogada ou invalida. Refaca a vinculacao com o gestor. A fila foi preservada.' }
    elseif ($http -eq 400) { $detail='Servidor rejeitou o lote. Verifique o relogio e procure suporte. A fila foi preservada.' }
} finally {
    try {
        $pending=@(Get-ChildItem (Join-Path $Root 'fila') -Filter '*.jsonl' -ErrorAction SilentlyContinue|Measure-Object Length -Sum)
        $row=@{status=$status;detail=$detail;sent=$sent;pending_bytes=[long]$pending[0].Sum;checked_at=(Get-Date).ToString('o');last_success=$lastSuccess}
        $path=Join-Path $Root 'sync-status.json';$row|ConvertTo-Json|Set-Content ($path+'.tmp') -Encoding UTF8
        Move-Item -LiteralPath ($path+'.tmp') -Destination $path -Force
    }catch{}
    $token=$null;$m.ReleaseMutex();$m.Dispose()
}
