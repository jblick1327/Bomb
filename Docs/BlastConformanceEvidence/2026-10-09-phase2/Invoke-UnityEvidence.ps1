param(
    [Parameter(Mandatory=$true)][string]$Operation,
    [Parameter(Mandatory=$true)][string]$Label
)
$blastProject = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
if ($blastProject -ne 'C:\Users\jblic\Desktop\Bomb\.worktrees\blast-conformance-probe') { throw 'Unexpected evidence checkout.' }
$blastArgs = @('command')
switch ($Operation) {
    'compile' { $blastArgs += 'recompile' }
    'compiled' { $blastArgs += 'recompile_status' }
    'status' { $blastArgs += 'test_status' }
    'console' { $blastArgs += 'console' }
    'counts' { $blastArgs += 'console_status' }
    'scenes' { $blastArgs += 'list_open_scenes' }
    'state' { $blastArgs += 'eval_file' }
    'measure' { $blastArgs += 'eval_file' }
    'edit' { $blastArgs += 'run_tests' }
    'play' { $blastArgs += 'run_tests' }
    default { throw 'Unknown evidence operation.' }
}
$blastArgs += @('--caller','plugin','--skill','unity-cli','--project-path',$blastProject,'--format','json')
switch ($Operation) {
    'edit' { $blastArgs += @('--','--mode','editor','--filter','Bomb.CanonicalDestruction.EditModeTests','--filter_type','assembly','--async_tests','true','--timeout','300') }
    'play' { $blastArgs += @('--','--mode','playmode','--filter','Bomb.CanonicalDestruction.PlayModeTests','--filter_type','assembly','--async_tests','true','--timeout','300') }
    'console' { $blastArgs += @('--','--tail','200','--level','warn') }
    'measure' { $blastArgs += @('--','--file',(Join-Path $PSScriptRoot 'MeasureFan.cs'),'--timeout','20000') }
    'state' { $blastArgs += @('--','--file',(Join-Path $PSScriptRoot 'FinalEditorState.cs'),'--timeout','20000') }
}
if ($Label -notmatch '^[a-z0-9-]+$') { throw 'Unsafe evidence label.' }
$blastInvocation = 'unity ' + (($blastArgs | ForEach-Object { "'" + $_.Replace("'","''") + "'" }) -join ' ')
[IO.File]::AppendAllText((Join-Path $PSScriptRoot 'invocations.log'),[DateTime]::UtcNow.ToString('o')+' '+$Label+' '+$blastInvocation+[Environment]::NewLine)
$blastRaw = & unity @blastArgs | Out-String
$blastExit = $LASTEXITCODE
[IO.File]::WriteAllText((Join-Path $PSScriptRoot ($Label+'.json')),$blastRaw)
Write-Output $blastRaw
exit $blastExit
