#requires -Version 5.1
function Get-MMQueueMutex {
    param([string]$Root)
    $bytes=[Text.Encoding]::UTF8.GetBytes($Root.ToLowerInvariant())
    $sha=[Security.Cryptography.SHA256]::Create()
    try { $suffix=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').Substring(0,24) } finally { $sha.Dispose() }
    New-Object Threading.Mutex -ArgumentList @($false, ('Local\MasterMonitorQueue-'+$suffix))
}
function Enter-MMQueue {
    param($Mutex)
    try { if (!$Mutex.WaitOne(10000)) { throw 'Fila ocupada por mais de 10 segundos.' } }
    catch [Threading.AbandonedMutexException] { } # O chamador ja possui o mutex abandonado.
}
function Add-MMQueue {
    param([string]$Root,[string]$Kind,$Row)
    if (!(Test-Path (Join-Path $Root 'cloud.json'))) { return }
    $dir=Join-Path $Root 'fila';New-Item $dir -ItemType Directory -Force|Out-Null
    $record=[ordered]@{event_id=[guid]::NewGuid().ToString();kind=$Kind;payload=$Row}
    $json=ConvertTo-Json -InputObject $record -Depth 6 -Compress
    $m=Get-MMQueueMutex $Root
    try {
        Enter-MMQueue $m
        try { [IO.File]::AppendAllText((Join-Path $dir 'active.jsonl'),$json+"`n",(New-Object Text.UTF8Encoding($false))) }
        finally { $m.ReleaseMutex() }
    } finally { $m.Dispose() }
}
function Rotate-MMQueue {
    param([string]$Root)
    $dir=Join-Path $Root 'fila';New-Item $dir -ItemType Directory -Force|Out-Null
    $m=Get-MMQueueMutex $Root
    try {
        Enter-MMQueue $m
        try {
            $active=Join-Path $dir 'active.jsonl'
            if ((Test-Path $active) -and (Get-Item $active).Length -gt 0) {
                $dest=Join-Path $dir ((Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmssfff')+'-'+[guid]::NewGuid().ToString('N')+'.jsonl')
                Move-Item -LiteralPath $active -Destination $dest
            }
        } finally { $m.ReleaseMutex() }
    } finally { $m.Dispose() }
}
function Read-MMQueueBatch {
    param([string]$Path,[int]$Limit=250)
    $reader=[IO.StreamReader]::new($Path,[Text.Encoding]::UTF8)
    try {
        $result=New-Object 'System.Collections.Generic.List[object]'
        $bytes=0
        while (!$reader.EndOfStream -and $result.Count -lt $Limit) {
            $line=$reader.ReadLine();if ($line.Trim()) {
                $size=[Text.Encoding]::UTF8.GetByteCount($line)
                if ($result.Count -gt 0 -and ($bytes+$size) -gt 900000) { break }
                $result.Add(($line|ConvertFrom-Json));$bytes+=$size
            }
        }
        return $result.ToArray()
    } finally { $reader.Dispose() }
}
function Complete-MMQueueBatch {
    param([string]$Path,[int]$Count)
    $reader=[IO.StreamReader]::new($Path,[Text.Encoding]::UTF8)
    $temp=$Path+'.tmp'
    $writer=[IO.StreamWriter]::new($temp,$false,(New-Object Text.UTF8Encoding($false)))
    try {
        $skipped=0
        while (!$reader.EndOfStream) {
            $line=$reader.ReadLine()
            if ($skipped -lt $Count -and $line.Trim()) { $skipped++;continue }
            if ($line.Trim()) { $writer.WriteLine($line) }
        }
    } finally { $reader.Dispose();$writer.Dispose() }
    if ((Get-Item $temp).Length -eq 0) { Remove-Item -LiteralPath $temp;Remove-Item -LiteralPath $Path }
    else { Move-Item -LiteralPath $temp -Destination $Path -Force }
}
