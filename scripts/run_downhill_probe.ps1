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

if (-not ('DownhillProbeJob' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class DownhillProbeJob
{
    [StructLayout(LayoutKind.Sequential)]
    public struct IO_COUNTERS
    {
        public ulong ReadOperationCount;
        public ulong WriteOperationCount;
        public ulong OtherOperationCount;
        public ulong ReadTransferCount;
        public ulong WriteTransferCount;
        public ulong OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct JOBOBJECT_BASIC_LIMIT_INFORMATION
    {
        public long PerProcessUserTimeLimit;
        public long PerJobUserTimeLimit;
        public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize;
        public UIntPtr MaximumWorkingSetSize;
        public uint ActiveProcessLimit;
        public UIntPtr Affinity;
        public uint PriorityClass;
        public uint SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION
    {
        public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
        public IO_COUNTERS IoInfo;
        public UIntPtr ProcessMemoryLimit;
        public UIntPtr JobMemoryLimit;
        public UIntPtr PeakProcessMemoryUsed;
        public UIntPtr PeakJobMemoryUsed;
    }

    const uint JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x00002000;
    const int JobObjectExtendedLimitInformation = 9;

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr CreateJobObject(IntPtr lpJobAttributes, string lpName);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool SetInformationJobObject(IntPtr hJob, int infoType, IntPtr lpJobObjectInfo, uint cbJobObjectInfoLength);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool CloseHandle(IntPtr handle);

    public static IntPtr CreateKillOnCloseJob()
    {
        IntPtr job = CreateJobObject(IntPtr.Zero, null);
        if (job == IntPtr.Zero)
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());

        var info = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
        info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        int length = Marshal.SizeOf(typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION));
        IntPtr ptr = Marshal.AllocHGlobal(length);
        try
        {
            Marshal.StructureToPtr(info, ptr, false);
            if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation, ptr, (uint)length))
            {
                int error = Marshal.GetLastWin32Error();
                CloseHandle(job);
                throw new System.ComponentModel.Win32Exception(error);
            }
        }
        finally
        {
            Marshal.FreeHGlobal(ptr);
        }
        return job;
    }

    public static void Assign(IntPtr job, IntPtr process)
    {
        if (!AssignProcessToJobObject(job, process))
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    }

    public static void Close(IntPtr job)
    {
        if (job != IntPtr.Zero)
            CloseHandle(job);
    }
}
'@
}
$startedAt = Get-Date

Write-Host "============================================================"
Write-Host " Recomp Domination - bounded first-boot probe"
Write-Host "============================================================"
Write-Host "Runner:  $Runner"
Write-Host "ELF:     $Elf"
Write-Host "Timeout: $TimeoutSeconds seconds"
Write-Host ""

# Launch through cmd.exe with file redirection. PowerShell owns no redirected
# pipes, so timeout handling never waits for async stream-drain tasks.
$launchPath = Join-Path $Here ("probe_launch_" + $stamp + ".cmd")
$escapedRunner = $Runner.Replace("%", "%%")
$escapedElf = $Elf.Replace("%", "%%")
$escapedStdout = $stdoutPath.Replace("%", "%%")
$escapedStderr = $stderrPath.Replace("%", "%%")
$launchLines = @(
    "@echo off",
    "cd /d ""$Here""",
    """$escapedRunner"" ""$escapedElf"" 1>""$escapedStdout"" 2>""$escapedStderr""",
    "exit /b %ERRORLEVEL%"
)
[IO.File]::WriteAllLines($launchPath, $launchLines, [Text.Encoding]::ASCII)

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $env:ComSpec
$psi.WorkingDirectory = $Here
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.Arguments = '/d /s /c ""' + $launchPath + '""'

$process = New-Object System.Diagnostics.Process
$process.StartInfo = $psi
$jobHandle = [IntPtr]::Zero
$normalExitCode = 0

try {
    $jobHandle = [DownhillProbeJob]::CreateKillOnCloseJob()
    if (!$process.Start()) { throw 'Failed to start diagnostic runner wrapper.' }
    [DownhillProbeJob]::Assign($jobHandle, $process.Handle)

    $timedOut = !$process.WaitForExit($TimeoutSeconds * 1000)
    if ($timedOut) {
        Write-Warning 'Probe timeout reached; closing Windows Job Object to terminate the complete process tree.'
        [DownhillProbeJob]::Close($jobHandle)
        $jobHandle = [IntPtr]::Zero
        # Do not access the process object again after killing the job.
        Start-Sleep -Milliseconds 150
    }
    else {
        $normalExitCode = $process.ExitCode
    }
}
finally {
    if ($jobHandle -ne [IntPtr]::Zero) {
        [DownhillProbeJob]::Close($jobHandle)
        $jobHandle = [IntPtr]::Zero
    }
}

Remove-Item -Force -ErrorAction SilentlyContinue $launchPath
$exitCode = if ($timedOut) { 124 } else { $normalExitCode }
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
