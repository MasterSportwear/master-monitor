#requires -Version 5.1
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'Core.ps1')
. (Join-Path $PSScriptRoot 'Queue.ps1')
. (Join-Path $PSScriptRoot 'Chrome.ps1')
$script:root = Join-Path $env:LOCALAPPDATA 'MasterMonitor'
New-Item $script:root -ItemType Directory -Force | Out-Null
$script:mutex = New-Object Threading.Mutex -ArgumentList @($false, ('Local\MasterMonitor-' + [Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
if (!$script:mutex.WaitOne(0)) { exit }
$script:cfg = [pscustomobject]@{ Colaborador = $env:USERNAME; Setor = 'Nao definido'; IntervaloSegundos = 5; InatividadeSegundos = 300; RetencaoDias = 30 }
try { $script:cfg = Get-Content (Join-Path $script:root 'config.json') -Raw | ConvertFrom-Json } catch {}
$script:interval = [math]::Max(5,[math]::Min(60,[int]$script:cfg.IntervaloSegundos))
$script:idleLimit = [math]::Max(60,[int]$script:cfg.InatividadeSegundos)
$script:retention = [math]::Max(7,[math]::Min(365,[int]$script:cfg.RetencaoDias))
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class MMNative {
    [StructLayout(LayoutKind.Sequential)] public struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] public static extern bool GetLastInputInfo(ref LASTINPUTINFO info);
    [DllImport("kernel32.dll")] public static extern ulong GetTickCount64();
    [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access);
    [DllImport("user32.dll", SetLastError=true)] public static extern bool SwitchDesktop(IntPtr desktop);
    [DllImport("user32.dll")] public static extern bool CloseDesktop(IntPtr desktop);
    public static double Idle() {
        LASTINPUTINFO info = new LASTINPUTINFO(); info.cbSize = (uint)Marshal.SizeOf(info);
        if (!GetLastInputInfo(ref info)) return -1;
        return unchecked((uint)GetTickCount64() - info.dwTime) / 1000.0;
    }
    public static bool DesktopAvailable() {
        IntPtr h = OpenInputDesktop(0, false, 0x0100);
        if(h == IntPtr.Zero) return false;
        try { return SwitchDesktop(h); } finally { CloseDesktop(h); }
    }
}
'@
function Write-Op {
    param([string]$Type,[string]$Detail)
    Write-MMRow $script:root 'operacao' ([pscustomobject]@{ Horario = (Get-Date).ToString('o'); Tipo = $Type; Detalhe = $Detail })
}
$script:health = @{}
function Set-Health {
    param([string]$Component,[string]$Problem)
    if ($Problem) {
        if (!$script:health.ContainsKey($Component) -or $script:health[$Component] -ne $Problem) { Write-Op 'Falha de coleta' "$Component : $Problem" }
        $script:health[$Component] = $Problem
    } elseif ($script:health.ContainsKey($Component)) {
        $script:health.Remove($Component); Write-Op 'Coleta restabelecida' $Component
    }
}
$script:seen = New-Object 'System.Collections.Generic.HashSet[string]'
for ($d=0; $d -le 2; $d++) {
    foreach ($e in @(Read-MMRows $script:root (Get-Date).AddDays(-$d).ToString('yyyy-MM-dd') 'eventos')) { [void]$script:seen.Add($e.Chave) }
}
function Collect-Events {
    $rules = @(
        @{ Log='System'; Provider='Microsoft-Windows-Kernel-Power'; IDs=@(41); Type='Interrupcao inesperada' },
        @{ Log='System'; Provider='EventLog'; IDs=@(6005,6006,6008); Type='Inicializacao/desligamento' },
        @{ Log='System'; Provider='User32'; IDs=@(1074); Type='Desligamento solicitado' },
        @{ Log='System'; Provider='Microsoft-Windows-WER-SystemErrorReporting'; IDs=@(1001); Type='Bugcheck / possivel tela azul' },
        @{ Log='Application'; Provider='Application Hang'; IDs=@(1002); Type='Aplicativo travado' },
        @{ Log='Application'; Provider='Application Error'; IDs=@(1000); Type='Falha de aplicativo' }
    )
    foreach ($rule in $rules) {
        $component = 'Eventos/' + $rule.Provider
        try {
            $entries = @(Get-WinEvent -FilterHashtable @{ LogName=$rule.Log; ProviderName=$rule.Provider; Id=$rule.IDs; StartTime=(Get-Date).AddDays(-2) } -ErrorAction Stop)
            Set-Health $component ''
            foreach ($e in $entries) {
                $key = "$($e.LogName)|$($e.RecordId)|$($e.TimeCreated.ToString('o'))"
                if (!$script:seen.Contains($key)) {
                    $detail = [string]$e.Message
                    if ($detail.Length -gt 2400) { $detail = $detail.Substring(0,2400) + ' [resumido]' }
                    Write-MMRow $script:root 'eventos' ([pscustomobject]@{ Horario=$e.TimeCreated.ToString('o'); Tipo=$rule.Type; Origem=$e.ProviderName; ID=$e.Id; Escopo='Sistema inteiro'; Detalhe=$detail; Chave=$key }) $e.TimeCreated
                    [void]$script:seen.Add($key)
                }
            }
        } catch {
            if ($_.FullyQualifiedErrorId -like '*NoMatchingEventsFound*') { Set-Health $component '' }
            else { Set-Health $component $_.Exception.Message }
        }
    }
}
function Collect-Performance {
    $cpu = ''; $ram = $null; $disk = ''; $free = $null
    foreach ($item in @('CPU','RAM','Disco','Espaco')) {
        try {
            switch ($item) {
                'CPU' { $v = Get-CimInstance -OperationTimeoutSec 5 -ClassName Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'"; if ($null -eq $v.PercentProcessorTime) { throw 'Contador indisponivel' }; $cpu = [int]$v.PercentProcessorTime }
                'RAM' { $v = Get-CimInstance -OperationTimeoutSec 5 -ClassName Win32_OperatingSystem; $ram = [math]::Round(100 * (1 - $v.FreePhysicalMemory / $v.TotalVisibleMemorySize),1) }
                'Disco' { $v = Get-CimInstance -OperationTimeoutSec 5 -ClassName Win32_PerfFormattedData_PerfDisk_PhysicalDisk -Filter "Name='_Total'"; if ($null -eq $v.PercentIdleTime) { throw 'Contador indisponivel' }; $disk = [math]::Max(0,[math]::Min(100,100 - [int]$v.PercentIdleTime)) }
                'Espaco' { $v = Get-CimInstance -OperationTimeoutSec 5 -ClassName Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'"; if ($null -eq $v.FreeSpace) { throw 'Espaco indisponivel' }; $free = [math]::Round($v.FreeSpace / 1GB,1) }
            }
            Set-Health $item ''
        } catch { Set-Health $item $_.Exception.Message }
    }
    # CSV numerico com ponto decimal, independente da configuracao regional.
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $row = [pscustomobject]@{ Horario=(Get-Date).ToString('o'); CPU=[string]$cpu; RAM=''; Disco=[string]$disk; DiscoLivreGB='' }
    if ($null -ne $ram) { $row.RAM = ([double]$ram).ToString($inv) }
    if ($null -ne $free) { $row.DiscoLivreGB = ([double]$free).ToString($inv) }
    Write-MMRow $script:root 'desempenho' $row
}
function Update-Reports {
    for ($d=0; $d -le 2; $d++) {
        $day = (Get-Date).AddDays(-$d).ToString('yyyy-MM-dd')
        $exists = @(Get-ChildItem (Join-Path $script:root 'dados') -Filter "$day-*.csv" -ErrorAction SilentlyContinue)
        if ($exists.Count) { [void](Write-MMReport $script:root $day $script:cfg.Setor $env:COMPUTERNAME) }
    }
}
$script:clock = [Diagnostics.Stopwatch]::StartNew()
$script:lastTick = $null; $script:previous = $null; $script:hangs = @{}
$script:lastSync = -300.0; $script:syncProcess = $null
$script:lastPerf = -60.0; $script:lastEvents = -120.0; $script:lastReport = -120.0
function Sample-Usage {
    $now = Get-Date; $tick = $script:clock.Elapsed.TotalSeconds
    if ($null -ne $script:lastTick) {
        $elapsed = $tick - $script:lastTick
        if ($elapsed -gt ($script:interval * 3)) {
            Write-Op 'Lacuna' ("Sem amostragem por {0:N0} segundos. Possivel suspensao, lentidao ou bloqueio do coletor; causa nao determinada." -f $elapsed)
        } elseif ($null -ne $script:previous) {
            # Intervalo atribuido a amostra anterior, nunca extrapolado sobre lacunas.
            Write-MMRow $script:root 'uso' ([pscustomobject]@{ Horario=$script:previous.Time.ToString('o'); Aplicativo=$script:previous.App; Estado=$script:previous.State; Segundos=([math]::Round($elapsed,2)).ToString([Globalization.CultureInfo]::InvariantCulture) }) $script:previous.Time
            if($script:previous.Domain) { Write-MMRow $script:root 'dominios' ([pscustomobject]@{ Horario=$script:previous.Time.ToString('o'); Dominio=$script:previous.Domain; Segundos=([math]::Round($elapsed,2)).ToString([Globalization.CultureInfo]::InvariantCulture) }) $script:previous.Time }
        }
    }
    $script:lastTick = $tick
    $idle = [MMNative]::Idle()
    if ($idle -lt 0) { throw 'Nao foi possivel medir inatividade da sessao.' }
    $state = 'ativo'; $app = '(sem janela)'
    if (![MMNative]::DesktopAvailable()) { $state = 'sessao indisponivel' }
    elseif ($idle -ge $script:idleLimit) { $state = 'inativo' }
    $h = [MMNative]::GetForegroundWindow(); $processIdValue = [uint32]0
    [void][MMNative]::GetWindowThreadProcessId($h,[ref]$processIdValue)
    if ($processIdValue -gt 0 -and $state -ne 'sessao indisponivel') {
        try {
            $proc = Get-Process -Id $processIdValue -ErrorAction Stop
            $app = $proc.ProcessName + '.exe'
            if (!$proc.Responding -and (!$script:hangs.ContainsKey($app) -or ($now - $script:hangs[$app]).TotalMinutes -ge 5)) {
                Write-Op 'Possivel travamento' "$app nao respondeu ao Windows nesta amostra. Confirmar com os eventos."
                $script:hangs[$app] = $now
            }
        } catch { $app = '(processo indisponivel)' }
    } elseif ($state -eq 'ativo') { $state = 'sem janela' }
    $domain=''
    if($state -eq 'ativo' -and $app -eq 'chrome.exe') { $domain=Get-MMChromeDomain $script:root $now }
    $script:previous = @{ Time=$now; App=$app; State=$state; Domain=$domain }
    if($app -eq 'chrome.exe' -and $state -eq 'ativo'){ if($domain){return "$app | $state | $domain"}; return "$app | $state | Chrome: sem dominio disponivel (confira a extensao)" }
    return "$app | $state"
}
$form = New-Object Windows.Forms.Form
$form.Text = 'Master Monitor 2.1 - monitoramento informado'
$form.Size = New-Object Drawing.Size(670,430)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'; $form.MaximizeBox = $false
$label = New-Object Windows.Forms.Label
$label.Location = New-Object Drawing.Point(20,20); $label.Size = New-Object Drawing.Size(620,95)
$label.Font = New-Object Drawing.Font('Segoe UI',11)
$label.Text = "MONITORAMENTO ATIVO - $($script:cfg.Colaborador) | $($script:cfg.Setor)`r`nEste computador registra aplicativos, inatividade e falhas, com envio ao painel do gestor.`r`nCom a extensao ativada, registra o dominio da aba ativa do Chrome. Nao captura conteudo, teclas, mensagens ou tela."
$form.Controls.Add($label)
$status = New-Object Windows.Forms.Label
$status.Location = New-Object Drawing.Point(20,120); $status.Size = New-Object Drawing.Size(620,65)
$form.Controls.Add($status)
$open = New-Object Windows.Forms.Button; $open.Text = 'Relatorio de hoje'; $open.Location = New-Object Drawing.Point(20,200); $open.Size = New-Object Drawing.Size(185,38)
$open.Add_Click({ try { Update-Reports; $p = Join-Path (Join-Path $script:root 'relatorios') ((Get-Date).ToString('yyyy-MM-dd') + '.html'); if (Test-Path $p) { Start-Process $p } } catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message) } })
$form.Controls.Add($open)
$folder = New-Object Windows.Forms.Button; $folder.Text = 'Dados e relatorios'; $folder.Location = New-Object Drawing.Point(220,200); $folder.Size = New-Object Drawing.Size(185,38)
$folder.Add_Click({ Start-Process explorer.exe -ArgumentList ('"' + $script:root + '"') }); $form.Controls.Add($folder)
$stop = New-Object Windows.Forms.Button; $stop.Text = 'Encerrar monitor'; $stop.Location = New-Object Drawing.Point(420,200); $stop.Size = New-Object Drawing.Size(185,38)
$stop.Add_Click({ $form.Close() }); $form.Controls.Add($stop)
$footer = New-Object Windows.Forms.Label; $footer.Text = 'Minimizar mantem o monitor ativo na barra de tarefas. Fechar encerra e registra a parada.'
$cloudLabel = New-Object Windows.Forms.Label; $cloudLabel.Location = New-Object Drawing.Point(20,260); $cloudLabel.Size = New-Object Drawing.Size(620,55); $cloudLabel.Text = 'Sincronizacao: aguardando primeiro envio.'; $form.Controls.Add($cloudLabel)
$footer.Location = New-Object Drawing.Point(20,325); $footer.Size = New-Object Drawing.Size(620,50); $form.Controls.Add($footer)
$timer = New-Object Windows.Forms.Timer; $timer.Interval = $script:interval * 1000
$timer.Add_Tick({
    $timer.Stop()
    try {
        $t = $script:clock.Elapsed.TotalSeconds
        if (($t - $script:lastSync) -ge 300 -and ($null -eq $script:syncProcess -or $script:syncProcess.HasExited)) {
            $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $argsSync = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $PSScriptRoot 'Sync.ps1') + '"'
            try {
                $script:syncProcess = Start-Process $exe -ArgumentList $argsSync -WindowStyle Minimized -PassThru
                Set-Health 'Sincronizacao' ''
            } catch { Set-Health 'Sincronizacao' $_.Exception.Message }
            $script:lastSync = $t
        }
        $sp=Join-Path $script:root 'sync-status.json'
        if (Test-Path $sp) {
            try { $cs=Get-Content $sp -Raw -Encoding UTF8|ConvertFrom-Json; $cloudLabel.Text='Envio: '+$cs.detail+' Fila: '+[math]::Round($cs.pending_bytes/1MB,1)+' MB. Ultimo sucesso: '+$cs.last_success } catch {}
        }
        $current = Sample-Usage
        Set-Health 'Uso' ''
        $t = $script:clock.Elapsed.TotalSeconds
        if (($t - $script:lastPerf) -ge 30) { Collect-Performance; $script:lastPerf = $script:clock.Elapsed.TotalSeconds }
        if (($t - $script:lastEvents) -ge 120) { Collect-Events; $script:lastEvents = $script:clock.Elapsed.TotalSeconds }
        if (($t - $script:lastReport) -ge 120) { Update-Reports; Remove-MMExpired $script:root $script:retention; $script:lastReport = $script:clock.Elapsed.TotalSeconds }
        $status.Text = "Ultima amostra: $((Get-Date).ToString('HH:mm:ss')) | $current`r`nFalhas de coleta ativas: $($script:health.Count). Consulte Operacao no relatorio."
    } catch {
        $status.Text = 'Falha no monitor: ' + $_.Exception.Message
        try { Set-Health 'Uso' $_.Exception.Message } catch {}
    } finally { if (!$form.IsDisposed) { $timer.Start() } }
})
$form.Add_FormClosing({
    $timer.Stop()
    try { Write-Op 'Encerramento' 'Monitor encerrado na sessao. Uma parada abrupta pode nao gerar este registro.'; Update-Reports } catch {}
})
try {
    Write-Op 'Inicio' 'Monitor visivel iniciado. Envio automatico ao painel do gestor. Eventos tecnicos podem incluir as ultimas 48 horas.'
    $form.Add_Shown({ $timer.Start() })
    [Windows.Forms.Application]::Run($form)
} catch {
    [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Master Monitor - falha') | Out-Null
} finally {
    $timer.Dispose(); $form.Dispose(); $script:mutex.ReleaseMutex(); $script:mutex.Dispose()
}
