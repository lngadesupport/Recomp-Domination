param(
    [string]$Elf = "",
    [int]$TimeoutSeconds = 90,
    [int64]$MaxStreamCaptureBytes = 16777216
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Runner = Join-Path $Here "ps2EntryRunner.exe"

if (!(Test-Path -LiteralPath $Runner)) {
    throw "ps2EntryRunner.exe was not found beside this script."
}

if (!$Elf) {
    $candidate = Join-Path (Split-Path $Here -Parent) "SCUS_971.77"
    if (Test-Path -LiteralPath $candidate) {
        $Elf = $candidate
    }
    else {
        throw "SCUS_971.77 was not found. Pass -Elf with the full path."
    }
}

$Elf = (Resolve-Path -LiteralPath $Elf).Path

if ($TimeoutSeconds -lt 1) {
    throw "TimeoutSeconds must be at least 1."
}
if ($MaxStreamCaptureBytes -lt 1048576) {
    throw "MaxStreamCaptureBytes must be at least 1 MiB."
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$stdoutPath = Join-Path $Here ("probe_stdout_" + $stamp + ".log")
$stderrPath = Join-Path $Here ("probe_stderr_" + $stamp + ".log")
$combinedPath = Join-Path $Here ("first_boot_probe_" + $stamp + ".log")
$latestPath = Join-Path $Here "first_boot_probe_latest.log"
$metaPath = Join-Path $Here "first_boot_probe.json"

function Write-Utf8Text {
    param([System.IO.Stream]$Stream, [string]$Text)
    [byte[]]$bytes = (New-Object Text.UTF8Encoding($false)).GetBytes($Text)
    $Stream.Write($bytes, 0, $bytes.Length)
}

function Append-LogTail {
    param(
        [System.IO.Stream]$Destination,
        [string]$Source,
        [int64]$MaxBytes
    )

    if (!(Test-Path -LiteralPath $Source)) {
        Write-Utf8Text $Destination "[log file missing]`r`n"
        return [pscustomobject]@{ bytes = 0L; captured = 0L; truncated = $false }
    }

    $input = [IO.File]::Open($Source, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        [int64]$size = $input.Length
        [int64]$captured = [Math]::Min($size, $MaxBytes)
        [bool]$truncated = $size -gt $captured

        if ($truncated) {
            [void]$input.Seek(-$captured, [IO.SeekOrigin]::End)
            Write-Utf8Text $Destination ("[earlier output truncated; keeping last {0} bytes]`r`n" -f $captured)
        }

        $input.CopyTo($Destination)
        Write-Utf8Text $Destination "`r`n"

        return [pscustomobject]@{
            bytes = $size
            captured = $captured
            truncated = $truncated
        }
    }
    finally {
        $input.Dispose()
    }
}

$startedAt = Get-Date

Write-Host "============================================================"
Write-Host " Recomp Domination - bounded first-boot probe"
Write-Host "============================================================"
Write-Host "Runner:  $Runner"
Write-Host "ELF:     $Elf"
Write-Host "Timeout: $TimeoutSeconds seconds"
Write-Host ""

$arguments = '"' + $Elf.Replace('"', '\"') + '"'
$process = Start-Process `
    -FilePath $Runner `
    -ArgumentList $arguments `
    -WorkingDirectory $Here `
    -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath `
    -PassThru

$timedOut = !$process.WaitForExit($TimeoutSeconds * 1000)

if ($timedOut) {
    Write-Warning "Probe timeout reached; terminating diagnostic runner process tree."

    # Do not call an unbounded WaitForExit() after a timeout. On Windows,
    # redirected stdout/stderr can keep process handles alive even after the
    # direct child exits. Kill the whole tree and only use bounded waits.
    try {
        & taskkill.exe /PID $process.Id /T /F 2>$null | Out-Null
    }
    catch {
        Write-Warning ("taskkill failed: " + $_.Exception.Message)
    }

    try {
        if (!$process.HasExited) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
    }
    catch {}

    try {
        [void]$process.WaitForExit(5000)
    }
    catch {}
}
else {
    # The process already signaled completion through the bounded wait above.
    # Give redirected streams a small bounded drain window, never an infinite wait.
    try { [void]$process.WaitForExit(5000) } catch {}
}

$exitCode = if ($timedOut) { 124 } else { $process.ExitCode }
$endedAt = Get-Date

$combined = [IO.File]::Open($combinedPath, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::Read)
try {
    Write-Utf8Text $combined "=== Recomp Domination diagnostic probe ===`r`n"
    Write-Utf8Text $combined ("started={0}`r`n" -f $startedAt.ToString("o"))
    Write-Utf8Text $combined ("ended={0}`r`n" -f $endedAt.ToString("o"))
    Write-Utf8Text $combined ("timeout_seconds={0}`r`n" -f $TimeoutSeconds)
    Write-Utf8Text $combined ("timed_out={0}`r`n" -f $timedOut)
    Write-Utf8Text $combined ("exit_code={0}`r`n`r`n" -f $exitCode)

    Write-Utf8Text $combined "=== STDOUT (tail) ===`r`n"
    $stdoutInfo = Append-LogTail $combined $stdoutPath $MaxStreamCaptureBytes

    Write-Utf8Text $combined "`r`n=== STDERR (tail) ===`r`n"
    $stderrInfo = Append-LogTail $combined $stderrPath $MaxStreamCaptureBytes
}
finally {
    $combined.Dispose()
}

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
    stdout_bytes = [int64]$stdoutInfo.bytes
    stderr_bytes = [int64]$stderrInfo.bytes
    stdout_captured_bytes = [int64]$stdoutInfo.captured
    stderr_captured_bytes = [int64]$stderrInfo.captured
    stdout_truncated = [bool]$stdoutInfo.truncated
    stderr_truncated = [bool]$stderrInfo.truncated
    max_stream_capture_bytes = $MaxStreamCaptureBytes
}

[IO.File]::WriteAllText(
    $metaPath,
    ($meta | ConvertTo-Json -Depth 5),
    (New-Object Text.UTF8Encoding($false))
)

$triageScript = Join-Path $Here "triage_first_boot.ps1"
$triageOut = Join-Path $Here "first_boot_probe_triage.json"
if (Test-Path -LiteralPath $triageScript) {
    & $triageScript -Log $latestPath -Out $triageOut
}

$suggestScript = Join-Path $Here "suggest_bringup_fixes.ps1"
$suggestOut = Join-Path $Here "first_boot_probe_suggestions.json"
$stagedConfig = Join-Path $Here "downhill.auto.toml"
if (Test-Path -LiteralPath $suggestScript) {
    if (Test-Path -LiteralPath $stagedConfig) {
        & $suggestScript -Log $latestPath -Config $stagedConfig -Out $suggestOut
    }
    else {
        & $suggestScript -Log $latestPath -Out $suggestOut
    }
}

Write-Host ""
Write-Host "Diagnostic probe complete."
Write-Host "Timed out: $timedOut"
Write-Host "Exit code: $exitCode"
Write-Host "STDOUT bytes: $($stdoutInfo.bytes)"
Write-Host "STDERR bytes: $($stderrInfo.bytes)"
Write-Host "Combined log: $combinedPath"
Write-Host "Metadata: $metaPath"
if (Test-Path -LiteralPath $triageOut) { Write-Host "Triage: $triageOut" }
if (Test-Path -LiteralPath $suggestOut) { Write-Host "Suggestions: $suggestOut" }

exit $exitCode
