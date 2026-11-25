[CmdletBinding()]
param(
 [string]$ConfigPath=(Join-Path (Split-Path -Parent $PSScriptRoot) 'local.config.json'),
 [string]$MonoPlayer='', [string]$Il2CppPlayer='', [string]$OutputDirectory='',
 # P3: package the release builds (Build-BomGame.ps1 -Release -> Game-<backend>-Release) for testers.
 [switch]$Release
)
# Works in Windows PowerShell 5.1 and PowerShell 7. Packages the front-door game (Bomb.exe, Darryn's main menu first; F4) built by
# Build-BomGame.ps1 into build/validation/Game-Mono and Game-IL2CPP. A backend is packaged when its player exists; at least one is required.
# Each backend folder keeps its own Server/BOM-server.exe + Server/levels/*.json beside Bomb.exe, where BomHostServer.FindServer looks first.
function Get-RelativePath([string]$base,[string]$path){
 $b=[IO.Path]::GetFullPath($base).TrimEnd([char[]]@([char]92,[char]47))+[IO.Path]::DirectorySeparatorChar
 $p=[IO.Path]::GetFullPath($path)
 if(!$p.StartsWith($b,[StringComparison]::OrdinalIgnoreCase)){throw "Path $p is outside $b"}
 $p.Substring($b.Length)
}
$ErrorActionPreference='Stop'
$integration=Split-Path -Parent $PSScriptRoot
$config=Get-Content -LiteralPath $ConfigPath -Raw|ConvertFrom-Json
$suffix=if($Release){'-Release'}else{''}
if(!$MonoPlayer){$MonoPlayer=Join-Path $integration "build/validation/Game-Mono$suffix/Bomb.exe"}
if(!$Il2CppPlayer){$Il2CppPlayer=Join-Path $integration "build/validation/Game-IL2CPP$suffix/Bomb.exe"}
if(!$OutputDirectory){$OutputDirectory=Join-Path $integration ('build/packages/Windows-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'))}
if(Test-Path -LiteralPath $OutputDirectory){throw 'Choose a new package directory; existing packages are preserved.'}
$native=Join-Path $config.OdinRoot 'build'
$identity=Get-Content -LiteralPath (Join-Path $native 'bomcore.build.json') -Raw|ConvertFrom-Json
$backends=@(@('Mono',$MonoPlayer),@('IL2CPP',$Il2CppPlayer)|Where-Object{Test-Path -LiteralPath $_[1] -PathType Leaf})
if($backends.Count -eq 0){throw 'No client build found; build a Mono or IL2CPP player first.'}
$serverHash=(Get-FileHash -LiteralPath (Join-Path $native 'BOM-server.exe')).Hash
foreach($pair in $backends){$player=$pair[1]
 $home1=Split-Path -Parent $player
 foreach($need in @('Server/BOM-server.exe','Server/levels/yard.json','Server/levels/YardLevel.json','Server/levels/BridgeLevel.json','Server/levels/TowerLevel.json')){if(!(Test-Path -LiteralPath (Join-Path $home1 $need))){throw "$($pair[0]) game has no $need; rebuild with Build-BomGame.ps1"}}
 if((Get-FileHash -LiteralPath (Join-Path $home1 'Server/BOM-server.exe')).Hash -ne $serverHash){throw "$($pair[0]) game carries a different BOM-server.exe than $native"}
 $plugin=Join-Path (Split-Path -Parent $player) 'Bomb_Data/Plugins/x86_64/bomcore.dll'
 if((Get-FileHash -LiteralPath $plugin).Hash.ToLowerInvariant() -ne $identity.dll_sha256){throw "Client has a different native library: $player"}
}
foreach($name in @('BOM-server.exe','BOM-server.pdb','BOM.exe','BOM.pdb','bomcore.dll','bomcore.pdb')){if(!(Test-Path -LiteralPath (Join-Path $native $name))){throw "Missing native artifact: $name"}}
$output=[IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $output -Force|Out-Null
foreach($pair in $backends){
 $destination=Join-Path $output $pair[0];New-Item -ItemType Directory -Path $destination -Force|Out-Null
 foreach($item in Get-ChildItem -LiteralPath (Split-Path -Parent $pair[1])){
  if($item.Name -match 'BackUpThisFolder|BurstDebugInformation' -or $item.Name -eq 'Logs' -or $item.Name -like 'editor-*.log'){continue}
  Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $destination $item.Name) -Recurse -Force
 }
}
$symbols=Join-Path $output 'Symbols/native'
New-Item -ItemType Directory -Path $symbols -Force|Out-Null
foreach($name in @('BOM-server.pdb','BOM.pdb','bomcore.pdb')){Copy-Item -LiteralPath (Join-Path $native $name) -Destination (Join-Path $symbols $name)}
foreach($pair in $backends){
 $target=Join-Path $output ('Symbols/'+$pair[0]);New-Item -ItemType Directory -Path $target -Force|Out-Null
 foreach($file in Get-ChildItem -LiteralPath (Split-Path -Parent $pair[1]) -File -Filter '*.pdb' -Recurse){
  $relative=(Get-RelativePath (Split-Path -Parent $pair[1]) $file.FullName)
  $destination=Join-Path $target $relative;New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force|Out-Null
  Copy-Item -LiteralPath $file.FullName -Destination $destination
 }
}
Copy-Item -LiteralPath (Join-Path $integration 'README.md') -Destination (Join-Path $output 'DEVELOPER-README.md')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Launch-BomPackage.ps1') -Destination (Join-Path $output 'Launch-Bom.ps1')
@'
BOM for Windows (x64). Read PACKAGE-NOTES.md first when it is here.

Play on this PC:
  powershell -ExecutionPolicy Bypass -File .\Launch-Bom.ps1
This opens two game windows (Mono build) at Darryn's main menu. In window 1 press ONLINE, HOST GAME, START
(This PC only). In window 2 press ONLINE, JOIN GAME and keep 127.0.0.1 and the port. Add -Backend IL2CPP for
the AOT build or -Clients 1 for one window. You can also run Mono\Bomb.exe or IL2CPP\Bomb.exe directly.
OFFLINE in the main menu is Darryn's local game, unchanged.

LAN: on the host PC choose "LAN / direct IP" in HOST GAME; the Esc menu lists the addresses. On the other PC run
Launch-Bom.ps1 -Clients 1 (or Bomb.exe) and use JOIN GAME with the host's address and port. The first time, Windows
asks to allow BOM-server.exe: tick Private networks and press Allow.
The game starts and stops its own server (Server\BOM-server.exe beside Bomb.exe); closing the host's game ends it.

These Windows x64 builds use Unity 6000.2.14f1 and an optimized native library
with matching debug symbols. No Unity Editor or Odin compiler is needed to play.
Keep the complete Mono and IL2CPP folders together. Symbols are in the Symbols folder;
the IL2CPP backup directory name is retained there to preserve debugger paths.
Source and reproducible build/test instructions are in DEVELOPER-README.md.
'@ | Set-Content -LiteralPath (Join-Path $output 'README.txt') -Encoding utf8
$rows=@(Get-ChildItem -LiteralPath $output -File -Recurse|Sort-Object FullName|ForEach-Object {[ordered]@{path=(Get-RelativePath $output $_.FullName).Replace('\','/');bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant()}})
[ordered]@{schema_version=1;platform='Windows x64';unity='6000.2.14f1';configuration=$(if($Release){'Release Unity'}else{'Development Unity'})+'; optimized native with debug symbols';native_identity=$identity;files=$rows}|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $output 'manifest.json') -Encoding utf8
Write-Output "Windows package: $output"
