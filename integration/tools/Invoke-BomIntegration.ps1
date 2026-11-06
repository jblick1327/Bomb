[CmdletBinding()]
param(
    [ValidateSet('VerifyEnvironment','Build','Test')][string]$Task='VerifyEnvironment',
    [ValidateSet('Fast','Content','NativeInterop','NativeProof')][string]$Suite='Content',
    [ValidateRange(0,3600)][int]$Seconds=0,
    [string]$ConfigPath=(Join-Path (Split-Path -Parent $PSScriptRoot) 'local.config.json')
)
$ErrorActionPreference='Stop'
$integration=Split-Path -Parent $PSScriptRoot
$unityRoot=Split-Path -Parent $integration
$evidence=Join-Path $integration 'evidence/M0'
New-Item -ItemType Directory -Path $evidence -Force | Out-Null
$stamp=[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')
$report=Join-Path $evidence "$Task-$Suite-$stamp.json"
$result=[ordered]@{task=$Task;suite=$Suite;started_utc=$stamp;exit_code=1;status='failed';checks=@();errors=@()}
try {
    if (!(Test-Path -LiteralPath $ConfigPath)) { throw 'Copy local.config.example.json to local.config.json and supply the source/tool paths.' }
    $config=Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    if ($Task -eq 'Test' -and $Suite -eq 'NativeInterop') {
        & (Join-Path $PSScriptRoot 'Test-RealNativeInterop.ps1') -ConfigPath $ConfigPath -Seconds $Seconds
        if ($LASTEXITCODE -ne 0) { throw 'Real native interop failed.' }
    } elseif ($Task -eq 'Test' -and $Suite -eq 'NativeProof') {
        & (Join-Path $PSScriptRoot 'Test-NativeProof.ps1') -ConfigPath $ConfigPath
        if ($LASTEXITCODE -ne 0) { throw 'Native ABI proof failed.' }
    } elseif ($Task -eq 'Test' -and $Suite -eq 'Content') {
        # Unity originals are immutable. Odin manifests record the baseline for
        # semantic comparison; native source refactoring is explicitly in scope.
        $contentRoots=,@('unity-content.json',$unityRoot)
        foreach ($pair in $contentRoots) {
            $rows=Get-Content -LiteralPath (Join-Path $integration "baselines/$($pair[0])") -Raw | ConvertFrom-Json
            foreach ($row in $rows) {
                $path=Join-Path $pair[1] $row.path
                if (!(Test-Path -LiteralPath $path -PathType Leaf)) { $result.errors += "Missing original: $($row.path)"; continue }
                if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $row.sha256) { $result.errors += "Modified original: $($row.path)" }
            }
            $result.checks += @{manifest=$pair[0];files=$rows.Count}
        }
        if ($result.errors.Count) { throw 'Original content verification failed; see report.' }
    } elseif ($Task -eq 'VerifyEnvironment') {
        foreach ($item in @(@('Odin source',(Join-Path $config.OdinRoot 'src/main.odin')),@('Unity Editor',$config.UnityEditor),@('Odin compiler',$config.OdinCompiler))) {
            $exists=($item[1] -and (Test-Path -LiteralPath $item[1]))
            $result.checks += @{name=$item[0];available=[bool]$exists}
            if (!$exists) { $result.errors += "$($item[0]) unavailable" }
        }
        $result.checks += @{name='.NET SDK';available=[bool](Get-Command dotnet -ErrorAction SilentlyContinue)}
        if (!(Get-Command dotnet -ErrorAction SilentlyContinue)) { $result.errors += '.NET SDK unavailable' }
        $kit=Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10/Lib'
        $sdkFound=Test-Path -LiteralPath $kit
        $result.checks += @{name='System Windows SDK';available=$sdkFound}
        $portableSdk=$false
        if ($config.PSObject.Properties.Name -contains 'LibraryDirectories') {
            $portableSdk=@($config.LibraryDirectories).Count -ge 3
            foreach ($directory in $config.LibraryDirectories) { if (!(Test-Path -LiteralPath $directory)) { $portableSdk=$false } }
        }
        $result.checks += @{name='Configured portable library directories';available=$portableSdk}
        if (!$sdkFound -and !$portableSdk) { $result.errors += 'Windows SDK unavailable; portable SDK/linker configuration has not been supplied' }
        $result.checks += @{name='Unity license, native vendor linkage, Mono and IL2CPP runtime';status='unverified';note='File presence does not establish these runtime gates.'}
        if ($result.errors.Count) { throw 'Environment prerequisites missing; see report.' }
    } else {
        if (!$config.OdinCompiler -or !(Test-Path -LiteralPath $config.OdinCompiler)) { throw 'Configured Odin compiler unavailable.' }
        $priorPath=$env:PATH
        $priorLib=$env:LIB
        try {
            $env:PATH=(Split-Path -Parent $config.OdinCompiler)+';'+$env:PATH
            if ($config.PSObject.Properties.Name -contains 'LinkerDirectory') { $env:PATH=$config.LinkerDirectory+';'+$env:PATH }
            if ($config.PSObject.Properties.Name -contains 'LibraryDirectories') { $env:LIB=(@($config.LibraryDirectories) -join ';') }
            $arguments=@()
            if ($config.PSObject.Properties.Name -contains 'CompilerArguments') { $arguments=@($config.CompilerArguments) }
            $tasks=if($Task -eq 'Build'){@('Build','Server')}else{@('Test','NetTest')}
            foreach($nativeTask in $tasks) {
                $log=Join-Path $evidence "$nativeTask-$stamp.log"
                & (Join-Path $config.OdinRoot 'scripts/bom.ps1') -Task $nativeTask -CompilerArguments $arguments 2>&1 | Tee-Object -FilePath $log
                $result.checks += @{command="scripts/bom.ps1 $nativeTask";exit_code=0;log=(Split-Path -Leaf $log)}
            }
            if ($Task -eq 'Build') {
                & (Join-Path $config.OdinRoot 'scripts/build-client.ps1') -ConfigPath $ConfigPath
                if ($LASTEXITCODE -ne 0) { throw 'Real native client build failed.' }
            }
        } finally { $env:PATH=$priorPath; $env:LIB=$priorLib }
    }
    $result.exit_code=0
    $result.status='passed'
} catch { $result.errors += $_.Exception.Message }
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $report -Encoding utf8
Write-Output "Evidence: $report"
exit $result.exit_code
