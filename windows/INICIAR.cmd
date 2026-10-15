@echo off
if not exist "%LOCALAPPDATA%\MasterMonitor\app\Monitor.ps1" (
 echo Execute INSTALAR.cmd primeiro.
 pause
 exit /b 1
)
start "Master Monitor" /min "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -STA -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\MasterMonitor\app\Monitor.ps1"
