#requires -Version 5.1
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
try {
    $m = New-Object Threading.Mutex -ArgumentList @($false, ('Local\MasterMonitor-' + [Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
    if (!$m.WaitOne(0)) { $m.Dispose(); throw 'Feche a janela Master Monitor antes de desinstalar.' }
    try {
        $answer = [Windows.Forms.MessageBox]::Show('Remover os atalhos e o inicio automatico nesta conta? Os dados e relatorios serao preservados.','Desinstalar Master Monitor','YesNo','Question')
        if ($answer -ne 'Yes') { exit 0 }
        foreach ($dir in @([Environment]::GetFolderPath('Startup'),[Environment]::GetFolderPath('Desktop'))) {
            $path = Join-Path $dir 'Master Monitor.lnk'
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
        }
        Remove-Item 'HKCU:\Software\Google\Chrome\NativeMessagingHosts\com.mastersportwear.monitor' -Recurse -Force -ErrorAction SilentlyContinue
        $app = Join-Path (Join-Path $env:LOCALAPPDATA 'MasterMonitor') 'app'
        if (Test-Path -LiteralPath $app) { Remove-Item -LiteralPath $app -Recurse -Force }
        [Windows.Forms.MessageBox]::Show('Desinstalado. Remova tambem a extensao em chrome://extensions. Os dados permanecem em %LOCALAPPDATA%\MasterMonitor. Apague essa pasta manualmente se quiser excluir os registros.','Master Monitor') | Out-Null
    } finally { $m.ReleaseMutex(); $m.Dispose() }
} catch {
    [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Nao foi possivel desinstalar','OK','Error') | Out-Null
    exit 1
}
