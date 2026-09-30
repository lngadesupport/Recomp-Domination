param(
    [string]$GameRoot = "",
    [int]$MinOccurrences = 1,
    [int]$MaxCandidates = 16,
    [int]$ProbeSeconds = 90,
    [switch]$PlanOnly
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ($MinOccurrences -lt 1) { throw "MinOccurrences must be at least 1." }
if ($MaxCandidates -lt 1 -or $MaxCandidates -gt 64) { throw "MaxCandidates must be between 1 and 64." }
if ($ProbeSeconds -lt 1) { throw "ProbeSeconds must be at least 1." }

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if (!$GameRoot) {
    $parent = Split-Path $RepoRoot -Parent
    if (Test-Path -LiteralPath (Join-Path $parent "DownhillRecompiled\first_boot_probe_suggestions.json")) { $GameRoot = $parent }
    elseif (Test-Path -LiteralPath "D:\Recomp Domination\DownhillRecompiled\first_boot_probe_suggestions.json") { $GameRoot = "D:\Recomp Domination" }
    else { $GameRoot = $parent }
}
$GameRoot = [IO.Path]::GetFullPath($GameRoot)
$DistDir = Join-Path $GameRoot "DownhillRecompiled"
$SuggestionCandidates = @(
    (Join-Path $DistDir "first_boot_probe_suggestions.json"),
    (Join-Path $DistDir "first_boot_suggestions.json")
)
$SuggestionsPath = $SuggestionCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (!$SuggestionsPath) { throw "No bring-up suggestions JSON was found under $DistDir. Run the first probe before pass 2." }

$Elf = Join-Path $GameRoot "SCUS_971.77"
if (!(Test-Path -LiteralPath $Elf)) { throw "SCUS_971.77 was not found under $GameRoot." }

$data = Get-Content -Raw -LiteralPath $SuggestionsPath | ConvertFrom-Json
$rawCandidates = @($data.missing_function_candidates)
if ($rawCandidates.Count -eq 0) {
    Write-Host "No missing-function candidates were observed. Second pass is not needed." -ForegroundColor Green
    exit 0
}

$validated = New-Object System.Collections.Generic.List[object]
foreach ($candidate in $rawCandidates) {
    $addressText = [string]$candidate.address
    $occurrences = [int]$candidate.occurrences
    $already = [bool]$candidate.already_configured

    if ($already -or $occurrences -lt $MinOccurrences) { continue }
    if ($addressText -notmatch '(?i)^0x([0-9a-f]{8})$') { continue }

    [uint32]$pc = [Convert]::ToUInt32($Matches[1],16)
    if ($pc -lt [uint32]0x0010A000 -or $pc -ge [uint32]0x0029DCF0 -or (($pc -band 3) -ne 0)) { continue }

    $validated.Add([pscustomobject][ordered]@{
        address = ('0x{0:X8}' -f $pc)
        occurrences = $occurrences
        source = $candidate.first_log_line
    })
}

$selected = @(
    $validated |
        Sort-Object @{Expression="occurrences";Descending=$true}, @{Expression="address";Descending=$false} |
        Select-Object -First $MaxCandidates
)

$planPath = Join-Path $RepoRoot "analysis\local\second_pass_plan.json"
New-Item -ItemType Directory -Force -Path (Split-Path $planPath -Parent) | Out-Null
$plan = [ordered]@{
    source_suggestions = $SuggestionsPath
    min_occurrences = $MinOccurrences
    max_candidates = $MaxCandidates
    observed_candidates = $rawCandidates.Count
    validated_candidates = $validated.Count
    selected = $selected
    plan_only = [bool]$PlanOnly
}
[IO.File]::WriteAllText($planPath,($plan|ConvertTo-Json -Depth 7),(New-Object Text.UTF8Encoding($false)))

Write-Host "============================================================"
Write-Host " Recomp Domination - second-pass bring-up"
Write-Host "============================================================"
Write-Host ("Suggestions: " + $SuggestionsPath)
Write-Host ("Selected:    " + $selected.Count)
foreach ($item in $selected) {
    Write-Host ("  {0}  occurrences={1}" -f $item.address,$item.occurrences)
}
Write-Host ("Plan:        " + $planPath)

if ($selected.Count -eq 0) {
    Write-Host "No safe new entry-point candidate passed the second-pass gates." -ForegroundColor Green
    exit 0
}

if ($PlanOnly) {
    Write-Host "Plan-only mode: no configuration was modified." -ForegroundColor Yellow
    exit 0
}

$EntryFile = Join-Path $RepoRoot "config\downhill.extra_entry_points.local.txt"
$BackupFile = $null
if (Test-Path -LiteralPath $EntryFile) {
    $BackupFile = $EntryFile + ".before_second_pass_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".bak"
    Copy-Item -Force -LiteralPath $EntryFile -Destination $BackupFile
}

$existing = @()
if (Test-Path -LiteralPath $EntryFile) {
    $existing = @(
        Get-Content -LiteralPath $EntryFile |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -match '(?i)^0x[0-9a-f]{8}$' }
    )
}
$merged = @($existing + @($selected | ForEach-Object { $_.address }) | Sort-Object -Unique)
New-Item -ItemType Directory -Force -Path (Split-Path $EntryFile -Parent) | Out-Null
[IO.File]::WriteAllLines($EntryFile,$merged,(New-Object Text.UTF8Encoding($false)))

Write-Host ("Saved entry hints: " + $EntryFile) -ForegroundColor Green
if ($BackupFile) { Write-Host ("Backup: " + $BackupFile) }

$BuildScript = Join-Path $RepoRoot "scripts\build_downhill.ps1"
$buildArgs = @("-NoLogo","-NoProfile","-ExecutionPolicy","Bypass","-File",$BuildScript,"-GameRoot",$GameRoot)
& powershell.exe @buildArgs
$BuildRc = $LASTEXITCODE
$BuildMode = "single-file"

if ($BuildRc -ne 0) {
    Write-Warning ("Second-pass single-file build failed with code " + $BuildRc + "; retrying multi-file.")
    & powershell.exe @buildArgs -MultiFileOutput
    $BuildRc = $LASTEXITCODE
    $BuildMode = "multi-file"
}

if ($BuildRc -ne 0) {
    throw ("Second-pass build failed in both output modes. Last code: " + $BuildRc)
}

$ProbeScript = Join-Path $DistDir "run_downhill_probe.ps1"
if (!(Test-Path -LiteralPath $ProbeScript)) { throw "Second-pass build did not stage run_downhill_probe.ps1." }

& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $ProbeScript -Elf $Elf -TimeoutSeconds $ProbeSeconds
$ProbeRc = $LASTEXITCODE
if ($ProbeRc -ne 0 -and $ProbeRc -ne 124) {
    Write-Warning ("Second-pass probe exited with code " + $ProbeRc + ". Diagnostics remain usable.")
}

$result = [ordered]@{
    build_mode = $BuildMode
    build_exit_code = $BuildRc
    probe_exit_code = $ProbeRc
    accepted_entries = @($selected | ForEach-Object { $_.address })
    backup = $BackupFile
}
$resultPath = Join-Path $RepoRoot "analysis\local\second_pass_result.json"
[IO.File]::WriteAllText($resultPath,($result|ConvertTo-Json -Depth 5),(New-Object Text.UTF8Encoding($false)))

Write-Host ""
Write-Host "Second-pass bring-up completed." -ForegroundColor Green
Write-Host ("Build mode: " + $BuildMode)
Write-Host ("Probe exit: " + $ProbeRc)
Write-Host ("Result: " + $resultPath)
exit 0
