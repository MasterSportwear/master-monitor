$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../windows/Chrome.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('mm-chrome-test-'+[guid]::NewGuid().ToString('N'))
$dir=Join-Path $root 'chrome-snapshots';New-Item $dir -ItemType Directory -Force|Out-Null
function Snapshot($Name,$Domain,$Age,$Focus=$true){@{domain=$Domain;received_at=(Get-Date).ToUniversalTime().AddSeconds(-$Age).ToString('o');focused=$Focus}|ConvertTo-Json|Set-Content (Join-Path $dir $Name) -Encoding UTF8}
function Check($Expected){$actual=Get-MMChromeDomain $root;if($actual -ne $Expected){throw "Expected '$Expected', got '$actual'"}}
try{
 Check '';Snapshot 'one.json' 'drive.google.com' 1;Check 'drive.google.com'
 Snapshot 'one.json' 'drive.google.com' 22;Check ''
 Snapshot 'one.json' 'drive.google.com' 1 $false;Check ''
 Snapshot 'one.json' 'https://example.com/secret?q=token' 1;Check ''
 Snapshot 'one.json' 'drive.google.com' 1;Snapshot 'two.json' 'other.example' 1;Check ''
 Remove-Item (Join-Path $dir 'two.json');Check 'drive.google.com'
 'PASS Chrome: freshness, focus, domain validation and ambiguous profiles'
}finally{Remove-Item $root -Recurse -Force}
