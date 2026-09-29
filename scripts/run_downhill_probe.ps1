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

# Run a uniquely named copy behind cmd.exe. The shell owns file redirection;
# PowerShell owns no stdout/stderr pipes. This avoids the Windows PowerShell
# Start-Process redirection deadlock seen after forced termination.
$probeBase = "DownhillProbeRunner_" + $stamp
$probeExe = Join-Path $Here ($probeBase + ".exe")
$launchCmd = Join-Path $Here ("probe_launch_" + $stamp + ".cmd")
Copy-Item -Force -LiteralPath $Runner -Destination $probeExe

$launchLines = @(
    "@echo off",
    "cd /d ""$Here""",
    """$probeExe"" ""$Elf"" 1>""$stdoutPath"" 2>""$stderrPath""",
    "exit /b %ERRORLEVEL%"
)
[IO.File]::WriteAllLines($launchCmd, $launchLines, [Text.Encoding]::ASCII)

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $env:ComSpec
$psi.WorkingDirectory = $Here
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.Arguments = '/d /s /c ""' + $launchCmd + '""'

$wrapper = New-Object System.Diagnostics.Process
$wrapper.StartInfo = $psi
if (!$wrapper.Start()) { throw 'Failed to start diagnostic wrapper.' }

$waitMs = [int][Math]::Min([int64][int]::MaxValue, [int64]$TimeoutSeconds * 1000L)
$timedOut = -not $wrapper.WaitForExit($waitMs)

if ($timedOut) {
    Write-Host ("Probe timeout reached; terminating unique runner {0}..." -f $probeBase) -ForegroundColor Yellow

    # Kill only the uniquely named probe copy. No redirected Process object is
    # touched here, so there are no .NET stream pumps to drain.
    Write-Host "[watchdog] locating unique runner process..."
    $targets = @(Get-Process -Name $probeBase -ErrorAction SilentlyContinue)
    Write-Host ("[watchdog] runner matches: " + $targets.Count)
    foreach ($target in $targets) {
        Write-Host ("[watchdog] killing runner PID " + $target.Id)
        try {
            $target.Kill()
            Write-Host ("[watchdog] Kill() returned for PID " + $target.Id)
        }
        catch {
            Write-Warning ("Failed to kill probe PID {0}: {1}" -f $target.Id, $_.Exception.Message)
        }
        finally {
            Write-Host ("[watchdog] disposing runner PID " + $target.Id)
            $target.Dispose()
            Write-Host "[watchdog] runner Process disposed"
        }
    }

    # The cmd wrapper normally exits as soon as its child dies. Keep this wait
    # bounded and kill only the wrapper if Windows does not signal it promptly.
    Write-Host ("[watchdog] waiting up to 5s for wrapper PID " + $wrapper.Id)
    if (!$wrapper.WaitForExit(5000)) {
        Write-Warning ("Probe wrapper PID {0} did not exit after child termination; forcing wrapper exit." -f $wrapper.Id)
        try {
            Write-Host "[watchdog] forcing wrapper Kill()"
            $wrapper.Kill()
            Write-Host "[watchdog] wrapper Kill() returned"
        } catch {}
        Write-Host "[watchdog] waiting final 1s for wrapper"
        [void]$wrapper.WaitForExit(1000)
    }
    Write-Host "[watchdog] timeout cleanup complete"

    $exitCode = 124
}
else {
    $exitCode = $wrapper.ExitCode
}

Write-Host "[watchdog] disposing wrapper"
$wrapper.Dispose()
Write-Host "[watchdog] wrapper disposed"
Write-Host "[watchdog] removing temporary launcher/image"
Remove-Item -Force -ErrorAction SilentlyContinue $launchCmd,$probeExe
Write-Host "[watchdog] temporary cleanup returned"
$endedAt = Get-Date

Write-Host "[watchdog] opening combined log"
$combined = [IO.File]::Open($combinedPath, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::Read)
try {
    Write-Utf8Text $combined "=== Recomp Domination diagnostic probe ===`r`n"
    Write-Utf8Text $combined ("started={0}`r`n" -f $startedAt.ToString("o"))
    Write-Utf8Text $combined ("ended={0}`r`n" -f $endedAt.ToString("o"))
    Write-Utf8Text $combined ("timeout_seconds={0}`r`n" -f $TimeoutSeconds)
    Write-Utf8Text $combined ("timed_out={0}`r`n" -f $timedOut)
    Write-Utf8Text $combined ("exit_code={0}`r`n`r`n" -f $exitCode)

    Write-Utf8Text $combined "=== STDOUT (tail) ===`r`n"
    Write-Host "[watchdog] appending stdout"
    $stdoutInfo = Append-LogTail $combined $stdoutPath $MaxStreamCaptureBytes
    Write-Host "[watchdog] stdout appended"

    Write-Utf8Text $combined "`r`n=== STDERR (tail) ===`r`n"
    Write-Host "[watchdog] appending stderr"
    $stderrInfo = Append-LogTail $combined $stderrPath $MaxStreamCaptureBytes
    Write-Host "[watchdog] stderr appended"
}
finally {
    $combined.Dispose()
}

Write-Host "[watchdog] copying combined log to latest"
Copy-Item -Force $combinedPath $latestPath
Write-Host "[watchdog] latest log ready"

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

Write-Host "[watchdog] writing metadata"
[IO.File]::WriteAllText(
    $metaPath,
    ($meta | ConvertTo-Json -Depth 5),
    (New-Object Text.UTF8Encoding($false))
)
Write-Host "[watchdog] metadata ready"

$triageScript = Join-Path $Here "triage_first_boot.ps1"
$triageOut = Join-Path $Here "first_boot_probe_triage.json"
if (Test-Path -LiteralPath $triageScript) {
    Write-Host "[watchdog] running triage"
    & $triageScript -Log $latestPath -Out $triageOut
    Write-Host "[watchdog] triage returned"
}

$suggestScript = Join-Path $Here "suggest_bringup_fixes.ps1"
$suggestOut = Join-Path $Here "first_boot_probe_suggestions.json"
$stagedConfig = Join-Path $Here "downhill.auto.toml"
if (Test-Path -LiteralPath $suggestScript) {
    Write-Host "[watchdog] running suggestion parser"
    if (Test-Path -LiteralPath $stagedConfig) {
        & $suggestScript -Log $latestPath -Config $stagedConfig -Out $suggestOut
    }
    else {
        & $suggestScript -Log $latestPath -Out $suggestOut
    }
    Write-Host "[watchdog] suggestion parser returned"
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
