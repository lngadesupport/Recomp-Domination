param(
    [string]$Elf = "",
    [int]$TimeoutSeconds = 90
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Runner = Join-Path $Here "ps2EntryRunner.exe"
if (!(Test-Path -LiteralPath $Runner)) { throw "ps2EntryRunner.exe was not found beside this script." }

if (!$Elf) {
    $candidate = Join-Path (Split-Path $Here -Parent) "SCUS_971.77"
    if (Test-Path -LiteralPath $candidate) { $Elf = $candidate }
    else { throw "SCUS_971.77 was not found. Pass -Elf with the full path." }
}
$Elf = (Resolve-Path -LiteralPath $Elf).Path

if ($TimeoutSeconds -lt 1) { throw "TimeoutSeconds must be at least 1." }

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$stdoutPath = Join-Path $Here ("probe_stdout_" + $stamp + ".log")
$stderrPath = Join-Path $Here ("probe_stderr_" + $stamp + ".log")
$combinedPath = Join-Path $Here ("first_boot_probe_" + $stamp + ".log")
$latestPath = Join-Path $Here "first_boot_probe_latest.log"
$metaPath = Join-Path $Here "first_boot_probe.json"

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $Runner
$psi.Arguments = '"' + $Elf.Replace('"','\"') + '"'
$psi.WorkingDirectory = $Here
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true

$process = New-Object System.Diagnostics.Process
$process.StartInfo = $psi

$startedAt = Get-Date
Write-Host "Starting diagnostic probe for up to $TimeoutSeconds seconds..."
Write-Host "Runner: $Runner"
Write-Host "ELF:    $Elf"

if (!$process.Start()) { throw "Failed to start ps2EntryRunner.exe." }

$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()
$timedOut = !$process.WaitForExit($TimeoutSeconds * 1000)

if ($timedOut) {
    Write-Warning "Probe timeout reached; terminating diagnostic runner process."
    try { $process.Kill() } catch {}
    try { $process.WaitForExit() } catch {}
}
else {
    $process.WaitForExit()
}

$stdout = $stdoutTask.Result
$stderr = $stderrTask.Result
$exitCode = if ($timedOut) { 124 } else { $process.ExitCode }
$endedAt = Get-Date

[IO.File]::WriteAllText($stdoutPath, $stdout, (New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText($stderrPath, $stderr, (New-Object Text.UTF8Encoding($false)))

$combined = @(
    "=== Recomp Domination diagnostic probe ===",
    ("started=" + $startedAt.ToString("o")),
    ("ended=" + $endedAt.ToString("o")),
    ("timeout_seconds=" + $TimeoutSeconds),
    ("timed_out=" + $timedOut),
    ("exit_code=" + $exitCode),
    "",
    "=== STDOUT ===",
    $stdout,
    "",
    "=== STDERR ===",
    $stderr
) -join [Environment]::NewLine

[IO.File]::WriteAllText($combinedPath, $combined, (New-Object Text.UTF8Encoding($false)))
Copy-Item -Force $combinedPath $latestPath

$meta = [ordered]@{
    runner = $Runner
    elf = $Elf
    started = $startedAt.ToString("o")
    ended = $endedAt.ToString("o")
    duration_seconds = [math]::Round(($endedAt - $startedAt).TotalSeconds, 3)
    timeout_seconds = $TimeoutSeconds
    timed_out = $timedOut
    exit_code = $exitCode
    stdout_log = $stdoutPath
    stderr_log = $stderrPath
    combined_log = $combinedPath
}
[IO.File]::WriteAllText($metaPath, ($meta | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))

$triageScript = Join-Path $Here "triage_first_boot.ps1"
$triageOut = Join-Path $Here "first_boot_probe_triage.json"
if (Test-Path -LiteralPath $triageScript) { & $triageScript -Log $latestPath -Out $triageOut }

$suggestScript = Join-Path $Here "suggest_bringup_fixes.ps1"
$suggestOut = Join-Path $Here "first_boot_probe_suggestions.json"
$stagedConfig = Join-Path $Here "downhill.auto.toml"
if (Test-Path -LiteralPath $suggestScript) {
    if (Test-Path -LiteralPath $stagedConfig) { & $suggestScript -Log $latestPath -Config $stagedConfig -Out $suggestOut }
    else { & $suggestScript -Log $latestPath -Out $suggestOut }
}

Write-Host ""
Write-Host "Diagnostic probe complete."
Write-Host "Timed out: $timedOut"
Write-Host "Exit code: $exitCode"
Write-Host "Combined log: $combinedPath"
Write-Host "Metadata: $metaPath"
if (Test-Path -LiteralPath $triageOut) { Write-Host "Triage: $triageOut" }
if (Test-Path -LiteralPath $suggestOut) { Write-Host "Suggestions: $suggestOut" }

exit $exitCode
