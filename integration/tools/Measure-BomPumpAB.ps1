[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Session,[string]$Label='')
# Pump-thread A/B (ABI 1.7): summarises one timed Start-BomNetwork run.
# Reads <Session>/player-N-net.jsonl (BomNetRecorder, --bom-net-out) and <Session>/server.log (INPUT lines),
# prints the metrics as JSON and writes <Session>/ab-metrics.json. Windows PowerShell 5.1 and PowerShell 7.
$ErrorActionPreference='Stop'
function Stat([double[]]$values){
 if(!$values -or $values.Count -eq 0){return [ordered]@{n=0;mean=$null;p50=$null;p95=$null;max=$null}}
 $sorted=$values|Sort-Object
 $pick={param($q)$sorted[[Math]::Min($sorted.Count-1,[int][Math]::Ceiling($q*$sorted.Count)-1)]}
 [ordered]@{n=$sorted.Count;mean=[Math]::Round(($values|Measure-Object -Average).Average,3);p50=[Math]::Round((& $pick 0.5),3);p95=[Math]::Round((& $pick 0.95),3);max=[Math]::Round($sorted[-1],3)}
}
$clients=@()
foreach($file in (Get-ChildItem -LiteralPath $Session -Filter 'player-*-net.jsonl'|Sort-Object Name)){
 $rows=@(Get-Content -LiteralPath $file.FullName|Where-Object {$_.Trim()}|ForEach-Object {$_|ConvertFrom-Json})
 if($rows.Count -eq 0){continue}
 # Only rows with a running clock count for lead/delay/RTT (connection_state 2 = connected).
 $live=@($rows|Where-Object {$_.connection_state -eq 2 -and $_.rtt_ms -gt 0})
 $first=$rows[0];$last=$rows[-1]
 $rtt=@($live|ForEach-Object {[double]$_.rtt_ms})
 # Quantisation: share of RTT samples sitting within 0.5 ms of a 60 Hz frame multiple (16.667 ms).
 $onFrame=@($rtt|Where-Object {$m=$_/16.6667;[Math]::Abs($m-[Math]::Round($m))*16.6667 -lt 0.5}).Count
 $clients+=[ordered]@{
  client=$file.BaseName -replace '-net$','';rows=$rows.Count;seconds=[Math]::Round($last.t-$first.t,1)
  pump_running=$last.pump_running;debug_hitches=$last.debug_hitches
  stall_count=$last.stall_count;input_count=$last.input_count-$first.input_count
  lead_ticks=Stat @($live|ForEach-Object {[double]$_.lead_ticks})
  interp_delay_ticks=Stat @($live|ForEach-Object {[double]$_.interp_delay_ticks})
  rtt_ms=Stat $rtt;rtt_on_60hz_multiple=if($rtt.Count){[Math]::Round($onFrame/$rtt.Count,3)}else{$null}
  prediction_mode_switches=$last.prediction_mode_switches;conservative_transitions=$last.conservative_transitions;recoveries=$last.recoveries
  pump_ticks=$last.pump_ticks;pump_late_count=$last.pump_late_count;pump_max_gap_ms=$last.pump_max_gap_ms
  pump_lock_wait_max_ms=$last.pump_lock_wait_max_ms;pump_lock_wait_p99_ms=$last.pump_lock_wait_p99_ms
  main_lock_wait_max_ms=$last.main_lock_wait_max_ms;main_lock_wait_p99_ms=$last.main_lock_wait_p99_ms
  clock_drift_ms_max=(($rows|ForEach-Object {[Math]::Abs([double]$_.clock_drift_ms)}|Measure-Object -Maximum).Maximum)
  heartbeat_neutral_ticks=$last.heartbeat_neutral_ticks;max_frame_ms=(($rows|Measure-Object max_frame_ms -Maximum).Maximum)
 }
}
$server=[ordered]@{}
$log=Join-Path $Session 'server.log'
if(Test-Path -LiteralPath $log){
 foreach($line in (Get-Content -LiteralPath $log)){
  if($line -match '^INPUT client=(\d+) .*accepted=(\d+) .*late=(\d+) starved=(\d+) neutralized=(\d+)'){
   # Counters are cumulative per connection; keep the last report for each client.
   $server["client$($Matches[1])"]=[ordered]@{accepted=[long]$Matches[2];late=[long]$Matches[3];starved=[long]$Matches[4];neutralized=[long]$Matches[5]}
  }
 }
 $server.tick_overruns=@(Get-Content -LiteralPath $log|Where-Object {$_ -match 'server tick overrun'}).Count
}
$result=[ordered]@{label=$Label;session=(Resolve-Path -LiteralPath $Session).Path;clients=$clients;server=$server}
$json=$result|ConvertTo-Json -Depth 6
Set-Content -LiteralPath (Join-Path $Session 'ab-metrics.json') -Value $json -Encoding UTF8
$json
