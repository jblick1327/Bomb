[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('Run', 'Build', 'Test', 'Smoke', 'SmokeInput', 'SmokeEditor', 'SmokeMaterials', 'SmokeMenus', 'Soak', 'NetTest', 'ReplicationSoak')]
    [string]$Task = 'Run',
    [string[]]$CompilerArguments = @()
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot

# Keep compiler output and runtime captures in the same place from any shell location.
Push-Location -LiteralPath $projectRoot
try {
    New-Item -ItemType Directory -Path 'build', 'output' -Force | Out-Null
    # Odin uses directory-scoped packages. Assemble sources without putting
    # diagnostic tools or tests back in the maintained game source directory.
    $stage = "build/package-$([guid]::NewGuid().ToString('N'))"
    Copy-Item -LiteralPath 'src' -Destination $stage -Recurse
    Copy-Item -Path 'diagnostics/*.odin' -Destination $stage
    if ($Task -eq 'Test' -or $Task -eq 'NetTest') {
        # Odin packages are directory-scoped; stage tests with their package's
        # sources so they can exercise internal game and networking helpers.
        Copy-Item -Path 'tests/*_test.odin' -Destination $stage
        Copy-Item -Path 'tests/netcode/*_test.odin' -Destination "$stage/netcode"
        Get-ChildItem -LiteralPath $stage -Filter '*_test.odin' | ForEach-Object {
            $content = [System.IO.File]::ReadAllText($_.FullName)
            $content = $content.Replace('"../evidence/', '"../../evidence/')
            [System.IO.File]::WriteAllText($_.FullName, $content)
        }
    }
    if ($Task -eq 'Build') {
        $odinArguments = @('build', $stage, '-o:speed', '-out:build/BOM.exe')
    } elseif ($Task -eq 'Test') {
        $odinArguments = @('test', $stage, '-out:build/BOM-tests.exe')
    } elseif ($Task -eq 'NetTest') {
        $odinArguments = @('test', "$stage/netcode", '-out:build/BOM-nettest.exe', '-define:ODIN_TEST_TRACK_MEMORY=true', '-define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true', '-define:ODIN_TEST_ALWAYS_REPORT_MEMORY=true', '-define:ODIN_TEST_FANCY=false')
    } else {
        $runtimeFlags = @{
            Smoke = '--smoke'
            SmokeInput = '--smoke-input'
            SmokeEditor = '--smoke-editor'
            SmokeMaterials = '--smoke-materials'
            SmokeMenus = '--smoke-menus'
            Soak = '--soak'
            ReplicationSoak = '--replication-soak'
        }
        $odinArguments = @('run', $stage, '-out:build/BOM.exe')
        if ($Task -eq 'Soak' -or $Task -eq 'ReplicationSoak') { $odinArguments += '-o:speed' }
        if ($runtimeFlags.ContainsKey($Task)) {
            $odinArguments += @('--', $runtimeFlags[$Task])
        }
    }

    # Insert compiler options before the runtime argument separator, if present.
    $separator = [array]::IndexOf($odinArguments, '--')
    if ($separator -ge 0) {
        $odinArguments = $odinArguments[0..($separator - 1)] + $CompilerArguments + $odinArguments[$separator..($odinArguments.Count - 1)]
    } else { $odinArguments += $CompilerArguments }

    # Windows PowerShell treats redirected native stderr as error records, even
    # for Odin's normal test progress. Use the process exit code for success.
    $ErrorActionPreference = 'Continue'
    try {
        & odin @odinArguments 2>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                $_.Exception.Message
            } else {
                $_
            }
        }
        $odinExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = 'Stop'
    }
    if ($odinExitCode -ne 0) {
        throw "Odin $Task failed with exit code $odinExitCode."
    }
} finally {
    if ($stage -and (Test-Path -LiteralPath $stage)) { Remove-Item -LiteralPath $stage -Recurse -Force }
    Pop-Location
}
