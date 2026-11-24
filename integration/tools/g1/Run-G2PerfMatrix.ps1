# G2 perf matrix (Windows PowerShell 5.1): F2/G1 protocol (Run-G1Perf.ps1) on every level with 1 and 2 windows,
# "before" = the pre-G2 path in the same build (--bom-clipped-source-art; G3 passes -BeforeExtra '--bom-stock-look'), "after" = the default path.
# Same 8 scripted host click-blasts in every run. Rule 3 is checked by Run-G1Perf.ps1 before each run.
param(
 [Parameter(Mandatory)][string]$Out,
 [int[]]$Levels=@(0,1,2,3),
 [int[]]$Windows=@(1,2),
 [string[]]$Paths=@('before','after'),
 [int]$Seconds=100,
 [string]$Clicks='30:900,380|36:400,570|42:640,300|48:1000,560|54:300,400|60:800,500|66:640,450|72:1100,350',
 [string]$BeforeExtra='--bom-clipped-source-art'
)
$ErrorActionPreference='Continue'
$names=@('classic','yard','bridge','tower')
New-Item -ItemType Directory -Force -Path $Out|Out-Null
foreach($l in $Levels){foreach($w in $Windows){foreach($path in $Paths){
 $dir=Join-Path $Out ("{0}-{1}w-{2}" -f $names[$l],$w,$path)
 if(Test-Path (Join-Path $dir 'run.json')){Write-Host "skip $dir";continue} # rerun into the same folder skips finished runs
 $extra=if($path -eq 'before'){$BeforeExtra}else{''}
 for($try=0;$try -lt 10;$try++){ # wait for memory / leftovers to clear instead of failing the precheck
  $ram=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory/1MB;$mine=@(Get-Process Bomb,BOM-server -EA SilentlyContinue).Count
  if($ram -ge 4 -and $mine -eq 0){break};Start-Sleep -Seconds 10}
 Write-Host "== $dir"
 try{& (Join-Path $PSScriptRoot 'Run-G1Perf.ps1') -Level $l -Clients $w -Seconds $Seconds -Out $dir -Extra $extra -Clicks $Clicks|Out-Null}catch{Write-Host "FAILED $dir $_"}
 Start-Sleep -Seconds 5
}}}
