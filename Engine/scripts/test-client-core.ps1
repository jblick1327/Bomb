[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ConfigPath)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$config=Get-Content -LiteralPath $ConfigPath -Raw|ConvertFrom-Json
$oldPath=$env:PATH;$oldLib=$env:LIB
try {
 $env:PATH=$config.LinkerDirectory+';'+$env:PATH;$env:LIB=$config.LibraryDirectories -join ';'
 foreach($package in @('shared','ffi')) {
  # Box2D world creation and the ABI owner-thread fixtures run on one thread,
  # just as the production native client does. Parallel fixtures can race the
  # process-global Box2D world registry and violate the ABI's ownership contract.
  $arguments=@('test',(Join-Path $root "src/$package"),"-out:$(Join-Path $root "build/$package-tests.exe")",'-define:ODIN_TEST_THREADS=1','-define:ODIN_TEST_FANCY=false','-define:ODIN_TEST_TRACK_MEMORY=true','-define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true')+@($config.CompilerArguments)
  & $config.OdinCompiler @arguments
  if($LASTEXITCODE -ne 0){throw "$package client-core tests failed with exit $LASTEXITCODE"}
 }
}finally{$env:PATH=$oldPath;$env:LIB=$oldLib}
