$ErrorActionPreference='Stop'
$source=Split-Path $PSScriptRoot -Parent
foreach($p in Get-ChildItem (Join-Path $source 'windows') -Filter '*.ps1'){
 $tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile($p.FullName,[ref]$tokens,[ref]$errors)
 if($errors.Count){$errors|Format-List;throw "Falha de sintaxe: $($p.Name)"};Write-Output "PASS sintaxe: $($p.Name)"
}
. (Join-Path $source 'windows/Queue.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('mm-queue-test-'+[guid]::NewGuid().ToString('N'));New-Item $root -ItemType Directory|Out-Null
Set-Content (Join-Path $root 'cloud.json') '{}'
foreach($i in 1..507){Add-MMQueue $root 'uso' ([pscustomobject]@{Horario=(Get-Date).ToString('o');Aplicativo='Editor';Estado='ativo';Segundos='5';Detalhe="aspas `" e acento ç $i"})}
Rotate-MMQueue $root
$files=@(Get-ChildItem (Join-Path $root 'fila') -Filter '*.jsonl');if($files.Count -ne 1){throw 'Rotacao falhou'}
$path=$files[0].FullName;$batch=@(Read-MMQueueBatch $path)
if($batch.Count -ne 250){throw "Quantidade incorreta: $($batch.Count)"}
if($batch[0].payload.Detalhe -notmatch 'ç 1$'){throw 'UTF8 perdeu caracteres'}
$first=$batch[0].event_id
# Nao confirmar simula falha de envio: os mesmos UUIDs devem reaparecer.
$retry=@(Read-MMQueueBatch $path);if($retry[0].event_id -ne $first){throw 'Retry alterou ID'}
Complete-MMQueueBatch $path 250;$second=@(Read-MMQueueBatch $path);if($second.Count -ne 250 -or $second[0].event_id -eq $first){throw 'Avanco do lote incorreto'}
Complete-MMQueueBatch $path 250;$third=@(Read-MMQueueBatch $path);if($third.Count -ne 7){throw 'Perda de registros restantes'}
Complete-MMQueueBatch $path 7;if(Test-Path $path){throw 'Arquivo confirmado nao foi removido'}
Add-MMQueue $root 'uso' ([pscustomobject]@{Horario=(Get-Date).ToString('o');Aplicativo='Editor';Estado='ativo';Segundos='5'})
Rotate-MMQueue $root;$last=(Get-ChildItem (Join-Path $root 'fila') -Filter '*.jsonl')[0];if(@(Read-MMQueueBatch $last.FullName).Count -ne 1){throw 'Lote unitario incorreto'}
Write-Output 'PASS fila: 507 registros, UTF8, rotacao, lote parcial, retry estavel e confirmacao sem perda'

# Lotes de mensagens longas tambem respeitam o limite de bytes da API.
$bigRoot=Join-Path $root 'large';New-Item $bigRoot -ItemType Directory|Out-Null;Set-Content (Join-Path $bigRoot 'cloud.json') '{}'
foreach($i in 1..200){Add-MMQueue $bigRoot 'eventos' ([pscustomobject]@{Horario=(Get-Date).ToString('o');Detalhe=('界'*2400)})}
Rotate-MMQueue $bigRoot;$bigFile=(Get-ChildItem (Join-Path $bigRoot 'fila') -Filter '*.jsonl')[0]
$large=@(Read-MMQueueBatch $bigFile.FullName)
if($large.Count -ge 200 -or $large.Count -lt 1){throw 'Limite de bytes nao aplicado'}
$json=@{records=@($large)}|ConvertTo-Json -Depth 8 -Compress
if([Text.Encoding]::UTF8.GetByteCount($json) -gt 1000000){throw 'Lote de bytes excessivo'}
Write-Output 'PASS limite de bytes: mensagens Unicode longas divididas antes de 1 MB'
