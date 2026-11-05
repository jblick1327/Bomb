[CmdletBinding()]
param([string]$ConfigPath=(Join-Path (Split-Path -Parent $PSScriptRoot) 'local.config.json'))
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$config=Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$build=Join-Path $root 'build/native-proof'
$evidence=Join-Path $root 'evidence/M1'
New-Item -ItemType Directory -Path $build,$evidence,(Join-Path $build 'empty-nuget') -Force | Out-Null
$stamp=[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')
$result=[ordered]@{milestone='M1';status='failed';exit_code=1;commands=@();errors=@()}
$oldPath=$env:PATH
$oldLib=$env:LIB
function Invoke-ProofCommand([string]$Program,[string[]]$Arguments,[string]$Name) {
    $log=Join-Path $evidence "$Name-$stamp.log"
    Set-Content -LiteralPath $log -Value '' -Encoding utf8
    & $Program @Arguments 2>&1 | Tee-Object -FilePath $log
    $code=$LASTEXITCODE
    $result.commands+=@{program=(Split-Path -Leaf $Program);arguments=$Arguments;exit_code=$code;log=(Split-Path -Leaf $log)}
    if($code -ne 0){throw "$Name exited with $code"}
}
try {
    $env:PATH=$config.LinkerDirectory+';'+$env:PATH
    $env:LIB=$config.LibraryDirectories -join ';'
    $dll=Join-Path $build 'bomproof.dll'
    Invoke-ProofCommand $config.OdinCompiler (@('build',(Join-Path $root 'native-proof'),'-build-mode:dll',"-out:$dll")+@($config.CompilerArguments)) 'odin-build'
    $cExe=Join-Path $build 'proof_test.exe'
    Invoke-ProofCommand 'cl.exe' @('/nologo','/W4',(Join-Path $root 'native-proof/proof_test.c'),"/Fo$(Join-Path $build 'proof_test.obj')","/Fe$cExe",'/link',(Join-Path $build 'bomproof.lib'),'kernel32.lib') 'c-build'
    Invoke-ProofCommand $cExe @() 'c-test'
    $managed=Join-Path $build 'managed'
    Invoke-ProofCommand 'dotnet' @('build',(Join-Path $root 'native-proof/managed/Proof.csproj'),'--source',(Join-Path $build 'empty-nuget'),'--nologo','-o',$managed) 'dotnet-build'
    Copy-Item -LiteralPath $dll -Destination (Join-Path $managed 'bomproof.dll') -Force
    Invoke-ProofCommand 'dotnet' @((Join-Path $managed 'Proof.dll')) 'dotnet-test'
    $result.dll_sha256=(Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash.ToLowerInvariant()
    $result.exit_code=0
    $result.status='passed'
} catch { $result.errors+=$_.Exception.Message }
finally {$env:PATH=$oldPath;$env:LIB=$oldLib}
$report=Join-Path $evidence "native-proof-$stamp.json"
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $report -Encoding utf8
Write-Output "Evidence: $report"
exit $result.exit_code
