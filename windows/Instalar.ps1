#requires -Version 5.1
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
$syncGuard=$null;$syncHeld=$false
try {
    $notice=@'
MASTER MONITOR 2.0 - monitoramento informado com envio automatico

Registra aplicativos em primeiro plano, inatividade e diagnosticos do Windows.
Envia os registros pela internet ao Supabase do gestor a cada 5 minutos.
A janela de monitoramento permanece disponivel na barra de tarefas.
Nao registra sites, teclas, mensagens, senhas ou imagens da tela.

Instale na conta Windows do colaborador informado. Contas compartilhadas
nao identificam a pessoa presente. E preciso vincular esta maquina uma vez.
Registros locais sao auxiliares e podem ser alterados pelo usuario do perfil.

Deseja instalar ou atualizar nesta conta?
'@
    if([Windows.Forms.MessageBox]::Show($notice,'Master Monitor 2.0','YesNo','Information') -ne 'Yes'){exit}
    $root=Join-Path $env:LOCALAPPDATA 'MasterMonitor';$app=Join-Path $root 'app'
    $m=New-Object Threading.Mutex -ArgumentList @($false,('Local\MasterMonitor-'+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
    if(!$m.WaitOne(0)){$m.Dispose();throw 'Feche a janela Master Monitor antes de instalar ou atualizar.'}
    $m.ReleaseMutex();$m.Dispose()
    $syncGuard=New-Object Threading.Mutex -ArgumentList @($false,('Local\MasterMonitorSync-'+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
    try { $syncHeld=$syncGuard.WaitOne(10000) } catch [Threading.AbandonedMutexException] { $syncHeld=$true }
    if(!$syncHeld){throw 'Aguarde o envio em andamento terminar e tente instalar novamente.'}
    $required=@('Monitor.ps1','Core.ps1','Queue.ps1','Sync.ps1','Desinstalar.ps1','DESINSTALAR.cmd','INICIAR.cmd','PAINEL.html','LEIA-ME.html')
    foreach($name in $required){if(!(Test-Path (Join-Path $PSScriptRoot $name))){throw "Pacote incompleto: $name"}}
    New-Item $app -ItemType Directory -Force|Out-Null
    $existing=Join-Path $root 'cloud.json'
    $previousCloud=$null
    if(Test-Path $existing){$previousCloud=Get-Content $existing -Raw -Encoding UTF8|ConvertFrom-Json}
    $link=Join-Path $PSScriptRoot 'vinculo.json'
    if(!(Test-Path $link)){
        $dialog=New-Object Windows.Forms.OpenFileDialog
        $dialog.Title='Selecione o vinculo.json baixado no painel (Cancelar para usar instalacao existente ou digitar dados)'
        $dialog.Filter='Arquivo de vinculacao (*.json)|*.json'
        if($dialog.ShowDialog() -eq 'OK'){$link=$dialog.FileName}
        $dialog.Dispose()
    }
    if(Test-Path $link){$enrollment=Get-Content $link -Raw -Encoding UTF8|ConvertFrom-Json}
    elseif(!(Test-Path $existing)){
        $enrollment=[pscustomobject]@{api_url=(Read-Host 'URL da API fornecida no painel');code=(Read-Host 'Codigo de vinculacao fornecido no painel')}
    }else{$enrollment=$null}
    $enrollmentHash=$null
    if($null -ne $enrollment){
        $hash=[Security.Cryptography.SHA256]::Create()
        try{$enrollmentHash=([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes([string]$enrollment.code)))).Replace('-','').ToLowerInvariant()}finally{$hash.Dispose()}
        if($previousCloud.enrollment_hash -eq $enrollmentHash -and (Test-Path (Join-Path $root 'device.key'))){$enrollment=$null}
    }
    if($null -ne $enrollment){
        if($enrollment.api_url -notmatch '^https://[a-z0-9-]+\.supabase\.co/functions/v1/monitor-api$'){throw 'URL invalida. Use o arquivo baixado no painel.'}
        if($enrollment.code -notmatch '^mmpair_[a-f0-9]{64}$'){throw 'Codigo de vinculacao invalido.'}
        [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
        $body=@{code=$enrollment.code;computer=$env:COMPUTERNAME}|ConvertTo-Json -Compress
        try{$answer=Invoke-RestMethod -Uri ($enrollment.api_url+'/pair') -Method Post -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 25}
        catch{throw 'Nao foi possivel vincular. Confira internet, endereco e validade do codigo. Se o codigo ja foi consumido, gere um novo cadastro no painel.'}
        if($answer.token -notmatch '^mmdev_[a-f0-9]{64}$' -or !$answer.device.id){throw 'Resposta de vinculacao invalida.'}
        if($previousCloud.device_id -and $previousCloud.device_id -ne $answer.device.id){
            $oldQueue=Join-Path $root 'fila'
            if(Test-Path $oldQueue){
                $archive=Join-Path $root ('fila-anterior-'+[guid]::NewGuid().ToString('N'))
                Move-Item -LiteralPath $oldQueue -Destination $archive
            }
        }
        # DPAPI do Windows: token protegido para a conta atual, sem chave administrativa.
        $protected=ConvertTo-SecureString $answer.token -AsPlainText -Force|ConvertFrom-SecureString
        [IO.File]::WriteAllText((Join-Path $root 'device.key'),$protected)
        @{api_url=$enrollment.api_url;device_id=$answer.device.id;enrollment_hash=$enrollmentHash}|ConvertTo-Json|Set-Content $existing -Encoding UTF8
        @{Colaborador=$answer.device.collaborator;Setor=$answer.device.sector;IntervaloSegundos=5;InatividadeSegundos=300;RetencaoDias=30}|ConvertTo-Json|Set-Content (Join-Path $root 'config.json') -Encoding UTF8
        $answer=$null;$protected=$null
    }
    if(!(Test-Path (Join-Path $root 'device.key'))){throw 'Credencial local ausente. Baixe um novo vinculo no painel.'}
    foreach($name in $required){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $app $name) -Force}
    $shell=New-Object -ComObject WScript.Shell
    $exe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments='-NoProfile -STA -ExecutionPolicy Bypass -File "'+(Join-Path $app 'Monitor.ps1')+'"'
    foreach($dir in @([Environment]::GetFolderPath('Startup'),[Environment]::GetFolderPath('Desktop'))){
        $shortcut=$shell.CreateShortcut((Join-Path $dir 'Master Monitor.lnk'))
        $shortcut.TargetPath=$exe;$shortcut.Arguments=$arguments;$shortcut.WorkingDirectory=$app;$shortcut.WindowStyle=7
        $shortcut.Description='Monitoramento informado e sincronizacao com o painel do gestor.';$shortcut.Save()
    }
    [Windows.Forms.MessageBox]::Show('Instalado. O monitor sera aberto agora. Confira a confirmacao do primeiro envio na janela e a ultima comunicacao no painel.','Master Monitor 2.0')|Out-Null
    Start-Process $exe -ArgumentList $arguments -WindowStyle Minimized
}catch{[Windows.Forms.MessageBox]::Show($_.Exception.Message,'Falha na instalacao','OK','Error')|Out-Null;exit 1}
finally{if($syncGuard){if($syncHeld){$syncGuard.ReleaseMutex()};$syncGuard.Dispose()}}
