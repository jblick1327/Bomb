[CmdletBinding()]
param([switch]$Apply)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$targets = @('build', 'output')

foreach ($name in $targets) {
    $path = Join-Path $projectRoot $name
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $item = Get-Item -LiteralPath $path -Force
    if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Refusing to clean a non-directory or link: $path"
    }
    $resolved = (Resolve-Path -LiteralPath $path).Path
    if ($resolved -ne (Join-Path $projectRoot $name)) { throw "Unexpected target: $resolved" }
    $contents = @(Get-ChildItem -LiteralPath $path -Force -Recurse)
    if (@($contents | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) {
        throw "Refusing to clean a directory containing links: $path"
    }
    $files = @($contents | Where-Object { -not $_.PSIsContainer })
    $bytes = ($files | Measure-Object -Property Length -Sum).Sum
    if ($null -eq $bytes) { $bytes = 0 }
    Write-Host ("{0}: {1} files, {2:N0} bytes" -f $path, $files.Count, $bytes)
    $files | ForEach-Object { Write-Host "  $($_.FullName)" }
    if ($Apply) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
if (-not $Apply) { Write-Host 'Preview only. Run with -Apply to remove these directories.' }
