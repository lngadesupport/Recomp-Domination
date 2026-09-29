param(
    [string]$Elf = ""
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

Write-Host "============================================================"
Write-Host " Recomp Domination - logged first boot"
Write-Host "============================================================"
Write-Host "Runner: $Runner"
Write-Host "ELF:    $Elf"
Write-Host "Log:    $log"
Write-Host ""

$global:LASTEXITCODE = 0
& $Runner $Elf 2>&1 | Tee-Object -FilePath $log
$rc = $LASTEXITCODE

Copy-Item -Force $log $lastLog
[IO.File]::WriteAllText(
    (Join-Path $Here "first_boot_exit_code.txt"),
    [string]$rc,
    (New-Object Text.UTF8Encoding($false))
)

Write-Host ""
Write-Host "Runner exit code: $rc"
Write-Host "Latest boot log: $lastLog"

exit $rc
