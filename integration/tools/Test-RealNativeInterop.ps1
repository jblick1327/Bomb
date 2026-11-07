[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ConfigPath,[ValidateRange(0,3600)][int]$Seconds=0,[switch]$SkipBuild)
$ErrorActionPreference='Stop'
$integration=Split-Path -Parent $PSScriptRoot
$config=Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$root=$config.OdinRoot
$build=Join-Path $root 'build'
$evidence=Join-Path $integration 'evidence/M3'
New-Item -ItemType Directory -Path $evidence,(Join-Path $build 'empty-nuget') -Force | Out-Null
$stamp=[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')
$result=[ordered]@{scope='Real DLL ABI/lifecycle and optional UDP run; remaining M3 gates are tracked separately';status='failed';exit_code=1;commands=@();errors=@()}
$oldPath=$env:PATH;$oldLib=$env:LIB
function Run([string]$Program,[string[]]$Arguments,[string]$Name) {
 $log=Join-Path $evidence "$Name-$stamp.log"
 Set-Content -LiteralPath $log -Value '' -Encoding utf8
 & $Program @Arguments 2>&1 | Tee-Object -FilePath $log
 $code=$LASTEXITCODE
 $result.commands+=@{program=(Split-Path -Leaf $Program);arguments=$Arguments;exit_code=$code;log=(Split-Path -Leaf $log)}
 if($code -ne 0){throw "$Name exited with $code"}
}
try {
 $env:PATH=$config.LinkerDirectory+';'+$env:PATH;$env:LIB=$config.LibraryDirectories -join ';'
 if (!$SkipBuild) { Run 'pwsh' @('-NoProfile','-File',(Join-Path $root 'scripts/build-client.ps1'),'-ConfigPath',$ConfigPath) 'live-dll-build' }
 Run 'python' @((Join-Path $root 'scripts/generate-interop-caller.py')) 'generate-c-caller'
 $cExe=Join-Path $build 'layout-test.exe'
 Run 'cl.exe' @('/nologo','/W4',(Join-Path $root 'tests/interop/layout_test.c'),"/Fo$(Join-Path $build 'layout-test.obj')","/Fe$cExe",'/link',(Join-Path $build 'bomcore.lib'),'kernel32.lib') 'c-build'
 Run $cExe @() 'c-abi-lifetime-overflow'
 $managed=Join-Path $build 'interop'
 Run 'dotnet' @('build',(Join-Path $root 'tests/interop/Interop.csproj'),'--source',(Join-Path $build 'empty-nuget'),'--nologo','-o',$managed) 'managed-build'
 Copy-Item -LiteralPath (Join-Path $build 'bomcore.dll') -Destination (Join-Path $managed 'bomcore.dll') -Force
 Run 'dotnet' @((Join-Path $managed 'Interop.dll')) 'managed-abi-lifetime'
 if($Seconds -gt 0) { Run 'python' @((Join-Path $PSScriptRoot 'Run-LiveInterop.py'),'--config',$ConfigPath,'--seconds',"$Seconds") 'real-udp' }
 $result.native_identity=Get-Content -LiteralPath (Join-Path $build 'bomcore.build.json') -Raw | ConvertFrom-Json
 $result.exit_code=0;$result.status='passed'
} catch { $result.errors+=$_.Exception.Message }
finally {$env:PATH=$oldPath;$env:LIB=$oldLib}
$path=Join-Path $evidence "real-interop-$stamp.json"
$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding utf8
Write-Output "Evidence: $path"
exit $result.exit_code
