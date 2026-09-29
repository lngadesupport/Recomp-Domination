param(
    [string]$Elf = "",
    [int64]$MaxFunctionTraceTailBytes = 8388608
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
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$log = Join-Path $Here ("first_boot_" + $stamp + ".log")
$lastLog = Join-Path $Here "first_boot_latest.log"
$functionTraceSource = Join-Path $Here "ps2_log.txt"
$functionTraceStamped = Join-Path $Here ("first_boot_function_trace_" + $stamp + ".log")
$functionTraceLatest = Join-Path $Here "first_boot_function_trace_latest.log"

function Append-FileTail {
    param(
        [string]$Destination,
        [string]$Source,
        [int64]$MaxBytes
    )

    if (!(Test-Path -LiteralPath $Source)) { return }

    $input = [IO.File]::Open($Source,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    $output = [IO.File]::Open($Destination,[IO.FileMode]::Append,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    try {
        [int64]$size=$input.Length
        [int64]$capture=[Math]::Min($size,$MaxBytes)
        if($size -gt $capture){
            [void]$input.Seek(-$capture,[IO.SeekOrigin]::End)
            [byte[]]$note=(New-Object Text.UTF8Encoding($false)).GetBytes(
                ("[function trace truncated; keeping last {0} bytes]`r`n" -f $capture)
            )
            $output.Write($note,0,$note.Length)
        }
        $input.CopyTo($output)
    }
    finally {
        $input.Dispose()
        $output.Dispose()
    }
}

Write-Host "============================================================"
Write-Host " Recomp Domination - logged first boot"
Write-Host "============================================================"
Write-Host "Runner: $Runner"
Write-Host "ELF:    $Elf"
Write-Host "Log:    $log"
Write-Host ""

Remove-Item -Force -ErrorAction SilentlyContinue $functionTraceSource
$global:LASTEXITCODE = 0
& $Runner $Elf 2>&1 | Tee-Object -FilePath $log
$rc = $LASTEXITCODE

if (Test-Path -LiteralPath $functionTraceSource) {
    Copy-Item -Force $functionTraceSource $functionTraceStamped
    Copy-Item -Force $functionTraceSource $functionTraceLatest
    Add-Content -LiteralPath $log -Value ([Environment]::NewLine + "=== AGGRESSIVE FUNCTION TRACE (tail) ===")
    Append-FileTail -Destination $log -Source $functionTraceSource -MaxBytes $MaxFunctionTraceTailBytes
}

Copy-Item -Force $log $lastLog
[IO.File]::WriteAllText(
    (Join-Path $Here "first_boot_exit_code.txt"),
    [string]$rc,
    (New-Object Text.UTF8Encoding($false))
)

$triageScript = Join-Path $Here "triage_first_boot.ps1"
$triageOut = Join-Path $Here "first_boot_triage.json"
if (Test-Path -LiteralPath $triageScript) {
    & $triageScript -Log $lastLog -Out $triageOut
}
$suggestScript = Join-Path $Here "suggest_bringup_fixes.ps1"
$suggestOut = Join-Path $Here "first_boot_suggestions.json"
$stagedConfig = Join-Path $Here "downhill.auto.toml"
if (Test-Path -LiteralPath $suggestScript) {
    if (Test-Path -LiteralPath $stagedConfig) {
        & $suggestScript -Log $lastLog -Config $stagedConfig -Out $suggestOut
    } else {
        & $suggestScript -Log $lastLog -Out $suggestOut
    }
}

Write-Host ""
Write-Host "Runner exit code: $rc"
Write-Host "Latest boot log: $lastLog"
if (Test-Path -LiteralPath $functionTraceLatest) {
    Write-Host "Function trace: $functionTraceLatest"
}
if (Test-Path -LiteralPath $triageOut) {
    Write-Host "Triage report: $triageOut"
}
if (Test-Path -LiteralPath $suggestOut) {
    Write-Host "Bring-up suggestions: $suggestOut"
}

exit $rc
