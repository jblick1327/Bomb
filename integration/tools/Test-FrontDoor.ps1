[CmdletBinding()]
param(
 [switch]$SkipBuild,
 [ValidateSet('Mono','IL2CPP')][string]$Backend='Mono',
 [string]$PlayerPath='',
 [ValidateSet('ClassicYard','Yard','Bridge','Tower')][string]$Level='ClassicYard',
 [string]$ConfigPath=(Join-Path (Split-Path -Parent $PSScriptRoot) 'local.config.json')
)
# C5 front-door gate. Builds integration/build/validation/Game-<Backend>/Bomb.exe (Build-BomGame.ps1, F4) (MainMenuScene first, Server/ beside it)
# in the validation project, then runs Run-FrontDoor.py. Works in Windows PowerShell 5.1 and PowerShell 7.
# -Level (C6) hosts and joins that level from the menu picker: ClassicYard (default), Yard, Bridge or Tower.
# Files outside Assets/BOMIntegration (Darryn's MatchMenuUI.cs hook) must already be mirrored (rule 7, Sync); this checks it.
$ErrorActionPreference='Stop'
$integration=Split-Path -Parent $PSScriptRoot;$unityRoot=Split-Path -Parent $integration
$config=Get-Content -LiteralPath $ConfigPath -Raw|ConvertFrom-Json
$validation=[IO.Path]::GetFullPath($config.UnityValidationProject)
$output=Join-Path $integration ('build/validation/Game-'+$Backend)
if(!$PlayerPath){$PlayerPath=Join-Path $output 'Bomb.exe'}
if(!$SkipBuild){
 & (Join-Path $PSScriptRoot 'Build-BomGame.ps1') -Backend $Backend -ConfigPath $ConfigPath
}
python (Join-Path $PSScriptRoot 'Run-FrontDoor.py') --config $ConfigPath --player $PlayerPath --level $Level
if($LASTEXITCODE -ne 0){throw 'Front-door gate failed. Inspect its evidence/M8/frontdoor-* directory.'}
