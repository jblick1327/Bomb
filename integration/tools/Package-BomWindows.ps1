[CmdletBinding()]
param(
 [string]$ConfigPath=(Join-Path (Split-Path -Parent $PSScriptRoot) 'local.config.json'),
 [string]$MonoPlayer='', [string]$Il2CppPlayer='', [string]$OutputDirectory=''
)
$ErrorActionPreference='Stop'
$integration=Split-Path -Parent $PSScriptRoot
$config=Get-Content -LiteralPath $ConfigPath -Raw|ConvertFrom-Json
if(!$MonoPlayer){$MonoPlayer=Join-Path $integration 'build/validation/Mono/BombPerformance.exe'}
if(!$Il2CppPlayer){$Il2CppPlayer=Join-Path $integration 'build/validation/IL2CPP/BombPerformance.exe'}
if(!$OutputDirectory){$OutputDirectory=Join-Path $integration ('build/packages/Windows-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'))}
if(Test-Path -LiteralPath $OutputDirectory){throw 'Choose a new package directory; existing packages are preserved.'}
$native=Join-Path $config.OdinRoot 'build'
$identity=Get-Content -LiteralPath (Join-Path $native 'bomcore.build.json') -Raw|ConvertFrom-Json
foreach($player in @($MonoPlayer,$Il2CppPlayer)){
 if(!(Test-Path -LiteralPath $player -PathType Leaf)){throw "Missing client: $player"}
 $plugin=Join-Path (Split-Path -Parent $player) 'BombPerformance_Data/Plugins/x86_64/bomcore.dll'
 if((Get-FileHash -LiteralPath $plugin).Hash.ToLowerInvariant() -ne $identity.dll_sha256){throw "Client has a different native library: $player"}
}
foreach($name in @('BOM-server.exe','BOM-server.pdb','BOM.exe','BOM.pdb','bomcore.dll','bomcore.pdb')){if(!(Test-Path -LiteralPath (Join-Path $native $name))){throw "Missing native artifact: $name"}}
$output=[IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $output -Force|Out-Null
foreach($pair in @(@('Mono',$MonoPlayer),@('IL2CPP',$Il2CppPlayer))){
 $destination=Join-Path $output $pair[0];New-Item -ItemType Directory -Path $destination -Force|Out-Null
 foreach($item in Get-ChildItem -LiteralPath (Split-Path -Parent $pair[1])){
  if($item.Name -match 'BackUpThisFolder|BurstDebugInformation'){continue}
  Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $destination $item.Name) -Recurse -Force
 }
}
$server=Join-Path $output 'Server';$symbols=Join-Path $output 'Symbols/native'
New-Item -ItemType Directory -Path $server,$symbols -Force|Out-Null
foreach($name in @('BOM-server.exe','BOM.exe','bomcore.dll','bomcore.build.json')){Copy-Item -LiteralPath (Join-Path $native $name) -Destination (Join-Path $server $name)}
foreach($name in @('BOM-server.pdb','BOM.pdb','bomcore.pdb')){Copy-Item -LiteralPath (Join-Path $native $name) -Destination (Join-Path $symbols $name)}
foreach($pair in @(@('Mono',$MonoPlayer),@('IL2CPP',$Il2CppPlayer))){
 $target=Join-Path $output ('Symbols/'+$pair[0]);New-Item -ItemType Directory -Path $target -Force|Out-Null
 foreach($file in Get-ChildItem -LiteralPath (Split-Path -Parent $pair[1]) -File -Filter '*.pdb' -Recurse){
  $relative=[IO.Path]::GetRelativePath((Split-Path -Parent $pair[1]),$file.FullName)
  $destination=Join-Path $target $relative;New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force|Out-Null
  Copy-Item -LiteralPath $file.FullName -Destination $destination
 }
}
Copy-Item -LiteralPath (Join-Path $integration 'fixtures/network-yard/yard.json') -Destination (Join-Path $output 'yard.json')
Copy-Item -LiteralPath (Join-Path $integration 'README.md') -Destination (Join-Path $output 'DEVELOPER-README.md')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Launch-BomPackage.ps1') -Destination (Join-Path $output 'Launch-Bom.ps1')
@'
Run with PowerShell 7:
  ./Launch-Bom.ps1
This starts a local server and two Mono game windows. Add -Backend IL2CPP for the
AOT build, or -Clients 1 for one window. The first window is the host. Use A/D or
arrows to move, Space to jump, Esc for the menu and host mode selection.
The server closes after its host window closes. Other windows show disconnect.

These Windows x64 builds use Unity 6000.2.14f1 and an optimized native library
with matching debug symbols. No Unity Editor or Odin compiler is needed to play.
Keep the complete client directories together. Symbols are in the Symbols folder;
the IL2CPP backup directory name is retained there to preserve debugger paths.
Source and reproducible build/test instructions are in DEVELOPER-README.md.
'@ | Set-Content -LiteralPath (Join-Path $output 'README.txt') -Encoding utf8
$rows=@(Get-ChildItem -LiteralPath $output -File -Recurse|Sort-Object FullName|ForEach-Object {[ordered]@{path=[IO.Path]::GetRelativePath($output,$_.FullName).Replace('\','/');bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant()}})
[ordered]@{schema_version=1;platform='Windows x64';unity='6000.2.14f1';configuration='Development Unity; optimized native with debug symbols';native_identity=$identity;files=$rows}|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $output 'manifest.json') -Encoding utf8
Write-Output "Windows package: $output"
