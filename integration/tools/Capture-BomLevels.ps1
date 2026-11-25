[CmdletBinding()]
param(
 [string]$Player='',
 # Text, not int[]: `powershell -File ... -Levels 1,3` passes "1,3" as one string, which int[] reads as 13.
 [string]$Levels='0,1,2,3',
 [ValidateRange(10,1800)][int]$Seconds=90,
 [ValidateRange(1,120)][double]$ShotEvery=6,
 [ValidateRange(1,65535)][int]$Port=47380,
 [string]$OutDir='',
 [switch]$NoMove
)
# Visual review: for each level, two front-door game windows (Bomb.exe) host and join from the menu like players, play
# Elimination rounds (the host starts the next one), move on their own (--bom-debug-move) and save what each window
# shows every few seconds: <out>/<level>/play-host-tNNN.png and play-guest-tNNN.png, plus both player logs.
# One level at a time. Works in Windows PowerShell 5.1 and PowerShell 7. Levels: 0 Classic Yard, 1 Yard, 2 Bridge, 3 Tower.
$ErrorActionPreference='Stop'
$integration=Split-Path -Parent $PSScriptRoot
if(!$Player){$Player=Join-Path $integration 'build/validation/Game-Mono/Bomb.exe'}
if(!(Test-Path -LiteralPath $Player)){throw "Missing game build: $Player (Build-BomGame.ps1 -Backend Mono)"}
if(!$OutDir){$OutDir=Join-Path $integration ('evidence/VIS/capture-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))}
$names=@('classic-yard','yard','bridge','tower')
foreach($level in @($Levels -split '[,\s]+' | Where-Object { $_ } | ForEach-Object { [int]$_ })){
 if($level -lt 0 -or $level -gt 3){throw "Level $level is not 0..3"}
 $dir=[IO.Path]::GetFullPath((Join-Path $OutDir $names[$level]))
 New-Item -ItemType Directory -Path $dir -Force|Out-Null
 $procs=@()
 foreach($role in @('play-host','play-guest')){
  $arguments=@('--bom-frontdoor-test',('"'+$dir+'"'),'--bom-frontdoor-role',$role,'--bom-frontdoor-level',"$level",'--bom-frontdoor-port',"$Port",
   '--bom-frontdoor-seconds',"$Seconds",'--bom-frontdoor-shot-every',$ShotEvery.ToString([Globalization.CultureInfo]::InvariantCulture),
   '-screen-fullscreen','0','-screen-width','1280','-screen-height','720','-logFile',('"'+(Join-Path $dir "$role.log")+'"'))
  if(!$NoMove){$arguments+='--bom-debug-move'}
  $procs+=Start-Process -FilePath $Player -ArgumentList $arguments -WorkingDirectory (Split-Path -Parent $Player) -PassThru
  Start-Sleep -Seconds 2
 }
 $deadline=[DateTime]::UtcNow.AddSeconds($Seconds+240)
 foreach($p in $procs){
  $left=[int][Math]::Max(1000,($deadline-[DateTime]::UtcNow).TotalMilliseconds)
  if(!$p.WaitForExit($left)){$p.Kill();$p.WaitForExit();Write-Warning "$($names[$level]): a window timed out and was closed"}
 }
 $shots=@(Get-ChildItem -LiteralPath $dir -Filter *.png).Count
 $pass=Test-Path -LiteralPath (Join-Path $dir 'play-host-done.signal')
 Write-Output ("{0}: {1} screenshots, host finished={2}, {3}" -f $names[$level],$shots,$pass,$dir)
}
