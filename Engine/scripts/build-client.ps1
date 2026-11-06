[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ConfigPath)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$config=Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$build=Join-Path $root 'build'
New-Item -ItemType Directory -Path $build -Force | Out-Null
& python (Join-Path $PSScriptRoot 'generate-client-abi.py')
if($LASTEXITCODE -ne 0){throw 'ABI generation failed'}
$hasher=[System.Security.Cryptography.IncrementalHash]::CreateHash([System.Security.Cryptography.HashAlgorithmName]::SHA256)
try {
    $paths=@('src/shared','src/netcode','src/ffi','bindings') | ForEach-Object { Get-ChildItem -LiteralPath (Join-Path $root $_) -File -Recurse }
    foreach($file in ($paths | Sort-Object FullName)) {
        $relative=[IO.Path]::GetRelativePath($root,$file.FullName).Replace('\','/')
        $hasher.AppendData([Text.Encoding]::UTF8.GetBytes("$relative`0"))
        $hasher.AppendData([IO.File]::ReadAllBytes($file.FullName))
    }
    $sourceHash=[Convert]::ToHexString($hasher.GetHashAndReset()).ToLowerInvariant()
} finally {$hasher.Dispose()}
$tag=[Convert]::ToInt64($sourceHash.Substring(0,15),16)
$oldPath=$env:PATH;$oldLib=$env:LIB
try {
    $env:PATH=$config.LinkerDirectory+';'+$env:PATH
    $env:LIB=$config.LibraryDirectories -join ';'
    $dll=Join-Path $build 'bomcore.dll'
    $arguments=@('build',(Join-Path $root 'src/ffi'),'-build-mode:dll','-o:speed',"-out:$dll","-define:BOM_CORE_BUILD_TAG=$tag")+@($config.CompilerArguments)
    & $config.OdinCompiler @arguments
    if($LASTEXITCODE -ne 0){throw "Native client build exited $LASTEXITCODE"}
    $compiler=(& $config.OdinCompiler version | Out-String).Trim()
    $schema=Get-Content -LiteralPath (Join-Path $root 'bindings/bom-abi.json') -Raw|ConvertFrom-Json
    $commit=(& git -C $root rev-parse HEAD 2>$null|Out-String).Trim()
    [ordered]@{abi_major=$schema.abi_major;abi_minor=$schema.abi_minor;source_commit=$commit;source_sha256=$sourceHash;build_tag=$tag;dll_sha256=(Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash.ToLowerInvariant();compiler=$compiler;game_protocol=3;canonical_version=2;client='shared native client, no managed codec';validation='See integration/tasks.json and integration/evidence for executed gates.'} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $build 'bomcore.build.json') -Encoding utf8
    Write-Output "Native client identity: $sourceHash ($tag)"
} finally {$env:PATH=$oldPath;$env:LIB=$oldLib}
