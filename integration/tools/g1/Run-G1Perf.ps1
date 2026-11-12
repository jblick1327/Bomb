# G1 measurement harness (Windows PowerShell 5.1), F2's protocol (with --bom-perf-manual: no scripted held input, real input kept) (integration/evidence/F2/tools/Run-F2Perf.ps1) plus scripted
# host click-blasts at fixed times and window positions, so a flag-off and a flag-on run see the same blasts.
#   --bom-frontdoor-test (C5 menu driver, caps 60 fps, vSync 0), --bom-perf-out (BomPerformanceProbe per-frame rows), 1 window, Sandbox.
# -Extra is extra player arguments separated by '|', e.g. '--bom-g1|--bom-levels|C:\...\levels-g1'.
param(
 [Parameter(Mandatory)][int]$Level,
 [int]$Seconds=100,
 [Parameter(Mandatory)][string]$Out,
 [string]$Exe='C:\Users\jblic\Desktop\Bomb-integration\integration\build\validation\Game-Mono\Bomb.exe',
 [string]$Extra='',
 [string]$Clicks='30:900,380|42:400,570|54:640,300|66:1000,560'
)
$ErrorActionPreference='Stop'
$Out=[IO.Path]::GetFullPath($Out) # the player resolves -logFile against its own folder, so never pass it a relative path
. 'C:\Users\jblic\Documents\BOM-Release\diag\ui.ps1'
$pkg=Split-Path -Parent $Exe
$free=(Get-PSDrive C).Free/1GB;$ram=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory/1MB
# Rule 3 counts Unity Editors. Unity Hub's helpers (Hub\resources\unity.exe, AppData\Local\Unity\bin\unity.exe, ~30 MB) are not editors (C3 finding).
$unity=@(Get-Process Unity -EA SilentlyContinue|Where-Object{$_.Path -like '*\Editor\Unity.exe'}).Count
$meta_helpers=@(Get-Process Unity -EA SilentlyContinue|Where-Object{$_.Path -notlike '*\Editor\Unity.exe'}|ForEach-Object{"$($_.Id) $($_.Path)"})
$mine=@(Get-Process Bomb,BOM-server -EA SilentlyContinue).Count
New-Item -ItemType Directory -Force -Path $Out|Out-Null
$script:scratch=$Out
$meta=[ordered]@{level=$Level;seconds=$Seconds;exe=$Exe;extra=$Extra;clicks=$Clicks;free_c_gb=[math]::Round($free,2);free_ram_gb=[math]::Round($ram,2);unity=$unity;preexisting_bomb_or_server=$mine;unity_helpers=($meta_helpers -join '; ');
 power=(Get-CimInstance Win32_Battery -EA SilentlyContinue|ForEach-Object{"status=$($_.BatteryStatus) charge=$($_.EstimatedChargeRemaining)"}) -join ';';started=(Get-Date).ToString('o')}
if($unity -ne 0 -or $ram -lt 4 -or $mine -ne 0){$meta.result='precheck_failed';$meta|ConvertTo-Json|Set-Content (Join-Path $Out 'run.json');throw "precheck failed: unity=$unity ram=$ram bomb/server=$mine"}
$t0=Get-Date
$port=Get-Random -Minimum 47400 -Maximum 47900
function Q([string]$p){'"'+$p+'"'}
$hostArgs=@('-screen-fullscreen','0','-screen-width','1280','-screen-height','720','--bom-frontdoor-port',"$port",'--bom-frontdoor-level',"$Level",
 '-logFile',(Q (Join-Path $Out 'host.log')),'--bom-frontdoor-test',(Q (Join-Path $Out 'signals-host')),'--bom-frontdoor-role','host',
 '--bom-perf-manual','--bom-perf-out',(Q (Join-Path $Out 'host-perf.json')),'--bom-perf-seconds',"$Seconds",'--bom-perf-warmup','5')+@($Extra.Split([char]'|')|Where-Object{$_})
$meta.args=$hostArgs -join ' '
$p=Start-Process -FilePath $Exe -ArgumentList $hostArgs -WorkingDirectory $pkg -PassThru -RedirectStandardOutput (Join-Path $Out 'host-stdout.log') -RedirectStandardError (Join-Path $Out 'host-stderr.log')
$deadline=(Get-Date).AddSeconds(120)
while(!(Test-Path (Join-Path $Out 'signals-host\host-hosted.signal'))){if($p.HasExited){break};if((Get-Date) -gt $deadline){break};Start-Sleep -Milliseconds 300}
$hosted=Get-Date;$meta.hosted_after_s=[math]::Round(($hosted-$t0).TotalSeconds,1)
Start-Sleep -Seconds 2;$p.Refresh();[void][W.U]::MoveWindow($p.MainWindowHandle,0,0,1296,759,$true)
$plan=@($Clicks.Split([char]'|')|Where-Object{$_}|ForEach-Object{$a=$_.Split(':');$xy=$a[1].Split(',');[pscustomobject]@{t=[double]$a[0];x=[int]$xy[0];y=[int]$xy[1];done=$false}})
$csv=Join-Path $Out 'process-samples.csv'
'utc,elapsed_s,wall_step_s,name,pid,cpu_pct_of_machine,cpu_pct_of_core,ws_mb,private_mb,gpu_util_pct'|Set-Content $csv
$prev=@{};$last=Get-Date;$maxStep=0;$cores=[Environment]::ProcessorCount;$hardStop=$t0.AddSeconds($Seconds+150);$shots=0
while($true){
 if($p.HasExited -or (Get-Date) -gt $hardStop){break}
 $since=((Get-Date)-$hosted).TotalSeconds
 foreach($c in $plan){if(!$c.done -and $since -ge $c.t){ClickXY $p $c.x $c.y;$c.done=$true;$meta["click_$($c.t)"]=[math]::Round($since,1)
  Start-Sleep -Milliseconds 250;Shot $p ("blast-{0:000}s-0.35s" -f $c.t)|Out-Null}}
 if($since -ge 80 -and $shots -eq 0){Shot $p 'settled-80s'|Out-Null;$shots=1}
 $servers=@(Get-Process BOM-server -EA SilentlyContinue|Where-Object{$_.StartTime -ge $t0})
 $list=@($p)+$servers
 $now=Get-Date;$step=($now-$last).TotalSeconds;$last=$now;if($step -gt $maxStep){$maxStep=$step}
 foreach($q in $list){if($null -eq $q){continue}
  try{$q.Refresh();$cpu=$q.TotalProcessorTime.TotalSeconds}catch{continue}
  $k=$q.Id;$pc='';$pcore=''
  if($prev.ContainsKey($k)){$dc=$cpu-$prev[$k].cpu;$dt=($now-$prev[$k].t).TotalSeconds;if($dt -gt 0){$pcore=[math]::Round(100*$dc/$dt,1);$pc=[math]::Round($pcore/$cores,1)}}
  $prev[$k]=@{cpu=$cpu;t=$now}
  $role=if($k -eq $p.Id){'host'}else{$q.ProcessName}
  "{0},{1:N1},{2:N2},{3},{4},{5},{6},{7:N0},{8:N0},{9}" -f $now.ToUniversalTime().ToString('o'),($now-$t0).TotalSeconds,$step,$role,$k,$pc,$pcore,($q.WorkingSet64/1MB),($q.PrivateMemorySize64/1MB),''|Add-Content $csv
 }
 Start-Sleep -Milliseconds 200
}
if(!$p.HasExited){if(!$p.WaitForExit(20000)){Stop-Process -Id $p.Id -Force;$meta.killed_host=$true}};$meta.exit_host=$p.ExitCode
Start-Sleep -Seconds 7
$left=@(Get-Process BOM-server -EA SilentlyContinue|Where-Object{$_.StartTime -ge $t0})
foreach($s in $left){Stop-Process -Id $s.Id -Force;$meta.killed_server+=@($s.Id)}
$t1=Get-Date
$power=@(Get-WinEvent -FilterHashtable @{LogName='System';StartTime=$t0;EndTime=$t1} -EA SilentlyContinue|Where-Object{($_.Id -eq 42 -and $_.ProviderName -like '*Kernel-Power*') -or ($_.Id -eq 1 -and $_.ProviderName -like '*Power-Troubleshooter*') -or ($_.Id -eq 107 -and $_.ProviderName -like '*Kernel-Power*')})
$meta.ended=$t1.ToString('o');$meta.duration_s=[math]::Round(($t1-$t0).TotalSeconds,1);$meta.max_sample_step_s=[math]::Round($maxStep,2);$meta.sleep_events=$power.Count
$meta.power_end=(Get-CimInstance Win32_Battery -EA SilentlyContinue|ForEach-Object{"status=$($_.BatteryStatus) charge=$($_.EstimatedChargeRemaining)"}) -join ';'
$meta.result=if($power.Count -gt 0 -or $maxStep -gt 6){'drop_sleep_or_gap'}else{'ok'}
$meta|ConvertTo-Json -Depth 4|Set-Content (Join-Path $Out 'run.json')
$meta|ConvertTo-Json -Depth 4
