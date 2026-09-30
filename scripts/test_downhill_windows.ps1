param(
    [string]$GameRoot = 'D:\Recomp Domination',
    [ValidateRange(1,3600)][int]$TimeoutSeconds = 90,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$RepoRoot = Split-Path $PSScriptRoot -Parent
$GameRoot = [IO.Path]::GetFullPath($GameRoot)
$DistDir = Join-Path $GameRoot 'DownhillRecompiled'
$result = 1
$stage = 'validate'
$started = Get-Date
$reportDir = Join-Path $RepoRoot 'analysis\local'
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
$report = [ordered]@{ started = $started.ToString('o'); game_root = $GameRoot; timeout_seconds = $TimeoutSeconds; skip_build = [bool]$SkipBuild }

function Invoke-Step {
    param([string]$Script, [string[]]$Arguments = @())
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $Script @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Step failed ($LASTEXITCODE): $Script" }
}

try {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Run this command on Windows.' }
    if (!(Test-Path -LiteralPath (Join-Path $GameRoot 'SCUS_971.77') -PathType Leaf)) { throw "SCUS_971.77 missing in $GameRoot" }
    $stage = 'prepare-game-data'
    Invoke-Step (Join-Path $PSScriptRoot 'prepare_game_data.ps1') @('-GameRoot', $GameRoot)
    if (!$SkipBuild) {
        $stage = 'build'
        Invoke-Step (Join-Path $PSScriptRoot 'build_downhill.ps1') @('-GameRoot', $GameRoot, '-MultiFileOutput')
    }
    $stage = 'probe'
    $probe = Join-Path $DistDir 'run_downhill_probe.ps1'
    if (!(Test-Path -LiteralPath $probe)) { throw "Probe script missing: $probe" }
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $probe -Elf (Join-Path $GameRoot 'SCUS_971.77') -TimeoutSeconds $TimeoutSeconds
    $result = $LASTEXITCODE
    $report['probe_exit_code'] = $result
    $metaPath = Join-Path $DistDir 'first_boot_probe.json'
    if (Test-Path -LiteralPath $metaPath) {
        $meta = Get-Content -LiteralPath $metaPath -Raw | ConvertFrom-Json
        $report['timed_out'] = [bool]$meta.timed_out
        if ($meta.timed_out) { Write-Host 'Probe reached its time limit; inspect the diagnostics for boot progress.' }
    }
}
catch {
    $report['error'] = $_.Exception.Message
    Write-Host ("TEST FAILED at ${stage}: " + $_.Exception.Message) -ForegroundColor Red
    $result = 1
}
finally {
    $report['last_stage'] = $stage
    $report['exit_code'] = $result
    $report['ended'] = (Get-Date).ToString('o')
    $report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $reportDir 'windows_test.json') -Encoding UTF8
    try { Invoke-Step (Join-Path $PSScriptRoot 'collect_diagnostics.ps1') @('-GameRoot', $GameRoot) }
    catch { Write-Host ('Diagnostics collection failed: ' + $_.Exception.Message) -ForegroundColor Red; $result = 1 }
}
exit $result
