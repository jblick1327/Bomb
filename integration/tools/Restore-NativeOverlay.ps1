[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$NativeRoot,[switch]$AllowOverwrite)
$ErrorActionPreference='Stop'
$integration=Split-Path -Parent $PSScriptRoot
$root=[IO.Path]::GetFullPath($NativeRoot).TrimEnd('\','/')
if(!(Test-Path -LiteralPath (Join-Path $root 'src/main.odin'))){throw 'Extract the supplied BOM archive first and select its project root.'}
if(!$AllowOverwrite){throw 'This applies the reviewed integration overlay to an extracted source copy. Use -AllowOverwrite for that dedicated copy.'}
$archive=Join-Path $integration 'patches/M9-native-source-overlay.zip'
$locked=Get-Content -LiteralPath (Join-Path $integration 'patches/M9-native-source.json') -Raw|ConvertFrom-Json
if((Get-FileHash -LiteralPath $archive).Hash.ToLowerInvariant() -ne $locked.overlay_sha256){throw 'Native source overlay hash differs from its recorded identity.'}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip=[IO.Compression.ZipFile]::OpenRead($archive)
try{
 $entry=$zip.GetEntry('integration-source-overlay-manifest.json');$reader=[IO.StreamReader]::new($entry.Open())
 try{$manifest=$reader.ReadToEnd()|ConvertFrom-Json}finally{$reader.Dispose()}
 foreach($row in $manifest.files){
  $destination=[IO.Path]::GetFullPath((Join-Path $root $row.path))
  if(!$destination.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Overlay entry leaves its target root.'}
  $item=$zip.GetEntry($row.path);if(!$item){throw "Missing overlay entry: $($row.path)"}
  New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force|Out-Null
  [IO.Compression.ZipFileExtensions]::ExtractToFile($item,$destination,$true)
  if((Get-FileHash -LiteralPath $destination).Hash.ToLowerInvariant() -ne $row.sha256){throw "Restored source hash differs: $($row.path)"}
 }
 Write-Output "Restored $($manifest.files.Count) exact source files to $root"
 Write-Output 'Set the fingerprint culture to en-CA, point local.config.json at this copy, then run the unified Build task.'
}finally{$zip.Dispose()}
