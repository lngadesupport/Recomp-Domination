param(
    [string]$GameRoot = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if (!$GameRoot) {
    $parent = Split-Path $RepoRoot -Parent
    if (Test-Path -LiteralPath (Join-Path $parent "SCUS_971.77")) { $GameRoot = $parent }
    elseif (Test-Path -LiteralPath "D:\Recomp Domination\SCUS_971.77") { $GameRoot = "D:\Recomp Domination" }
    else { $GameRoot = $parent }
}
$GameRoot = [IO.Path]::GetFullPath($GameRoot)
$DistDir = Join-Path $GameRoot "DownhillRecompiled"
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$zip = Join-Path $GameRoot ("RecompDomination_Diagnostics_" + $stamp + ".zip")
$temp = Join-Path $env:TEMP ("RecompDominationDiag_" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $temp | Out-Null

function Copy-Diagnostic {
    param([string]$Source, [string]$Relative)
    if (!(Test-Path -LiteralPath $Source)) { return }
    $target = Join-Path $temp $Relative
    $dir = Split-Path $target -Parent
    if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Copy-Item -LiteralPath $Source -Destination $target -Force
}

try {
    Copy-Diagnostic (Join-Path $RepoRoot "config\downhill.auto.toml") "config\downhill.auto.toml"
    Copy-Diagnostic (Join-Path $RepoRoot "analysis\local\SCUS_971.77.identity.json") "analysis\SCUS_971.77.identity.json"
    Copy-Diagnostic (Join-Path $RepoRoot "analysis\local\environment.json") "analysis\environment.json"
    Copy-Diagnostic (Join-Path $RepoRoot "analysis\local\game_data_prepared.json") "analysis\game_data_prepared.json"
    Copy-Diagnostic (Join-Path $RepoRoot "analysis\local\SCUS_971.77.deep.json") "analysis\SCUS_971.77.deep.json"
    Copy-Diagnostic (Join-Path $RepoRoot "analysis\local\ghidra_map_report.json") "analysis\ghidra_map_report.json"
    Copy-Diagnostic (Join-Path $RepoRoot "analysis\local\ghidra_optional_status.json") "analysis\ghidra_optional_status.json"
    Copy-Diagnostic (Join-Path $RepoRoot "analysis\SCUS_971.77.functions.csv") "analysis\SCUS_971.77.functions.csv"
    Copy-Diagnostic (Join-Path $RepoRoot "analysis\SCUS_971.77.ghidra.toml") "analysis\SCUS_971.77.ghidra.toml"
    Copy-Diagnostic (Join-Path $RepoRoot "config\downhill.extra_entry_points.local.txt") "config\downhill.extra_entry_points.local.txt"
    Copy-Diagnostic (Join-Path $RepoRoot "analysis\local\last_build.json") "analysis\last_build.json"
    Copy-Diagnostic (Join-Path $RepoRoot "analysis\local\PS2Recomp.downhill.patch.diff") "analysis\PS2Recomp.downhill.patch.diff"
    Copy-Diagnostic (Join-Path $DistDir "build_report.json") "runtime\build_report.json"
    Copy-Diagnostic (Join-Path $DistDir "recompiled_report.json") "runtime\recompiled_report.json"
    Copy-Diagnostic (Join-Path $DistDir "runtime_stubs_report.json") "runtime\runtime_stubs_report.json"
    Copy-Diagnostic (Join-Path $DistDir "SCUS_971.77.deep.json") "runtime\SCUS_971.77.deep.json"
    Copy-Diagnostic (Join-Path $DistDir "first_boot_latest.log") "runtime\first_boot_latest.log"
    Copy-Diagnostic (Join-Path $DistDir "first_boot_triage.json") "runtime\first_boot_triage.json"
    Copy-Diagnostic (Join-Path $DistDir "first_boot_suggestions.json") "runtime\first_boot_suggestions.json"
    Copy-Diagnostic (Join-Path $DistDir "first_boot_exit_code.txt") "runtime\first_boot_exit_code.txt"
    Copy-Diagnostic (Join-Path $DistDir "first_boot_probe_latest.log") "runtime\first_boot_probe_latest.log"
    Copy-Diagnostic (Join-Path $DistDir "first_boot_probe_function_trace_latest.log") "runtime\first_boot_probe_function_trace_latest.log"
    Copy-Diagnostic (Join-Path $DistDir "first_boot_probe.json") "runtime\first_boot_probe.json"
    Copy-Diagnostic (Join-Path $DistDir "first_boot_probe_triage.json") "runtime\first_boot_probe_triage.json"
    Copy-Diagnostic (Join-Path $DistDir "first_boot_probe_suggestions.json") "runtime\first_boot_probe_suggestions.json"

    $latestBuildLog = Get-ChildItem -LiteralPath (Join-Path $RepoRoot "logs") -Filter "build_downhill_*.log" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latestBuildLog) { Copy-Diagnostic $latestBuildLog.FullName "logs\$($latestBuildLog.Name)" }

    $environment = New-Object System.Collections.Generic.List[string]
    $environment.Add("Collected: " + (Get-Date -Format o))
    $environment.Add("GameRoot: " + $GameRoot)
    $environment.Add("RepoRoot: " + $RepoRoot)
    try { $environment.Add("Git HEAD: " + ((& git -C $RepoRoot rev-parse HEAD) | Select-Object -First 1)) } catch {}
    try { $environment.Add("Git branch: " + ((& git -C $RepoRoot branch --show-current) | Select-Object -First 1)) } catch {}
    try { $environment.Add("CMake: " + ((& cmake --version) | Select-Object -First 1)) } catch {}
    try { $environment.Add("Git: " + ((& git --version) | Select-Object -First 1)) } catch {}
    $environment.Add("OS: " + [Environment]::OSVersion.VersionString)
    $environment.Add("PowerShell: " + $PSVersionTable.PSVersion.ToString())
    [IO.File]::WriteAllLines((Join-Path $temp "environment.txt"), $environment, (New-Object Text.UTF8Encoding($false)))

    # Deliberately exclude SCUS_971.77, ISO/BIN/CHD/RAR files and generated game data.
    if (Test-Path -LiteralPath $zip) { Remove-Item -Force $zip }
    Compress-Archive -Path (Join-Path $temp "*") -DestinationPath $zip -CompressionLevel Optimal
    Write-Host "Diagnostics package created:"
    Write-Host "  $zip"
}
finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
