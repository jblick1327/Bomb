[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('Run', 'Build', 'Test', 'Smoke', 'SmokeInput', 'SmokeEditor', 'SmokeMaterials', 'Soak')]
    [string]$Task = 'Run'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot

# Keep compiler output and runtime captures in the same place from any shell location.
Push-Location -LiteralPath $projectRoot
try {
    New-Item -ItemType Directory -Path 'build', 'output' -Force | Out-Null
    if ($Task -eq 'Build') {
        $odinArguments = @('build', 'src', '-o:speed', '-out:build/BOM.exe')
    } elseif ($Task -eq 'Test') {
        $odinArguments = @('test', 'src', '-out:build/BOM-tests.exe')
    } else {
        $runtimeFlags = @{
            Smoke = '--smoke'
            SmokeInput = '--smoke-input'
            SmokeEditor = '--smoke-editor'
            SmokeMaterials = '--smoke-materials'
            Soak = '--soak'
        }
        $odinArguments = @('run', 'src', '-out:build/BOM.exe')
        if ($Task -eq 'Soak') { $odinArguments += '-o:speed' }
        if ($runtimeFlags.ContainsKey($Task)) {
            $odinArguments += @('--', $runtimeFlags[$Task])
        }
    }

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
    Pop-Location
}
