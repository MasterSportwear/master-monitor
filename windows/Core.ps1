# Identificacao local registrada em cada linha para consolidacao entre maquinas.
function Get-MMProfile {
    param([string]$Root)
    if (!$script:MMProfileCache) { $script:MMProfileCache = @{} }
    $p = Join-Path $Root 'config.json'
    $stamp = ''
    if (Test-Path $p) { $stamp = (Get-Item $p).LastWriteTimeUtc.ToString('o') }
    if (!$script:MMProfileCache.ContainsKey($Root) -or $script:MMProfileCache[$Root].Stamp -ne $stamp) {
        $cfg = $null
        if ($stamp) { $cfg = Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json }
        $name = $env:USERNAME
        if ($cfg.Colaborador) { $name = $cfg.Colaborador }
        $script:MMProfileCache[$Root] = @{ Stamp=$stamp; Value=@{ Colaborador=$name; Computador=$env:COMPUTERNAME; Setor=$cfg.Setor } }
    }
    return $script:MMProfileCache[$Root].Value
}
# Master Monitor 1.0 - funcoes de dados e relatorios; compativel com PowerShell 5.1.
function Write-MMRow {
    param([string]$Root, [string]$Kind, [object]$Row, [datetime]$Date = (Get-Date))
    $profile = Get-MMProfile $Root
    foreach ($key in @('Colaborador','Computador','Setor')) {
        if (!$Row.PSObject.Properties[$key]) { $Row | Add-Member -NotePropertyName $key -NotePropertyValue $profile.$key }
    }
    $dir = Join-Path $Root 'dados'
    if (!(Test-Path $dir)) { New-Item $dir -ItemType Directory -Force | Out-Null }
    $file = Join-Path $dir ($Date.ToString('yyyy-MM-dd') + '-' + $Kind + '.csv')
    $Row | Export-Csv -LiteralPath $file -Delimiter ';' -NoTypeInformation -Encoding UTF8 -Append
    if (Get-Command Add-MMQueue -ErrorAction SilentlyContinue) { Add-MMQueue $Root $Kind $Row }
}
function Read-MMRows {
    param([string]$Root, [string]$Day, [string]$Kind)
    $p = Join-Path (Join-Path $Root 'dados') ($Day + '-' + $Kind + '.csv')
    if (Test-Path $p) { Import-Csv -LiteralPath $p -Delimiter ';' -Encoding UTF8 }
}
function Encode-MM { param($Value) [System.Net.WebUtility]::HtmlEncode([string]$Value) }
function Convert-MMTable {
    param([object[]]$Rows, [string[]]$Columns)
    if (!$Rows -or $Rows.Count -eq 0) { return '<p>Sem registros nesta categoria.</p>' }
    $out = '<table><thead><tr>'
    foreach ($c in $Columns) { $out += '<th>' + (Encode-MM $c) + '</th>' }
    $out += '</tr></thead><tbody>'
    foreach ($r in $Rows) {
        $out += '<tr>'
        foreach ($c in $Columns) { $out += '<td>' + (Encode-MM $r.$c) + '</td>' }
        $out += '</tr>'
    }
    $out + '</tbody></table>'
}
function Write-MMReport {
    param([string]$Root, [string]$Day, [string]$Sector, [string]$Computer)
    $payload = [ordered]@{ gerado = (Get-Date).ToString('dd/MM/yyyy HH:mm:ss zzz') }
    foreach ($kind in @('uso','desempenho','eventos','operacao','dominios')) {
        $rows = @(Read-MMRows $Root $Day $kind)
        foreach ($r in $rows) {
            if (!$r.Computador) { $r | Add-Member -NotePropertyName Computador -NotePropertyValue $Computer -Force }
            if (!$r.Setor) { $r | Add-Member -NotePropertyName Setor -NotePropertyValue $Sector -Force }
        }
        $payload[$kind] = @($rows)
    }
    $json = ConvertTo-Json -InputObject $payload -Depth 8 -Compress
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
    $template = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'PAINEL.html'),[Text.Encoding]::UTF8)
    $html = $template.Replace('__MM_EMBEDDED__',$encoded)
    $dir = Join-Path $Root 'relatorios'
    New-Item $dir -ItemType Directory -Force | Out-Null
    $dest = Join-Path $dir ($Day + '.html')
    $temp = $dest + '.tmp'
    [IO.File]::WriteAllText($temp,$html,(New-Object Text.UTF8Encoding($true)))
    Move-Item -LiteralPath $temp -Destination $dest -Force
    return $dest
}
function Remove-MMExpired {
    param([string]$Root, [int]$Days)
    $cut = (Get-Date).Date.AddDays(-$Days).ToString('yyyy-MM-dd')
    foreach ($sub in @('dados','relatorios')) {
        $dir = Join-Path $Root $sub
        if (Test-Path $dir) {
            Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}' -and $_.Name.Substring(0,10) -lt $cut } | Remove-Item -Force
        }
    }
}
