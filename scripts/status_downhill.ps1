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

function Test-PathBool([string]$Path) { return [bool](Test-Path -LiteralPath $Path) }
function Status-Line([string]$Name,[bool]$Ok,[string]$Detail) {
    $mark = if ($Ok) { "OK " } else { "-- " }
    $color = if ($Ok) { "Green" } else { "DarkGray" }
    Write-Host ($mark + $Name.PadRight(28) + $Detail) -ForegroundColor $color
}

$elf = Join-Path $GameRoot "SCUS_971.77"
$cdRootSidecar = Join-Path $GameRoot "downhill_cd_root.txt"
$cdImageSidecar = Join-Path $GameRoot "downhill_cd_image.txt"
$ghidraCsv = Join-Path $RepoRoot "analysis\SCUS_971.77.functions.csv"
$config = Join-Path $RepoRoot "config\downhill.auto.toml"
$identity = Join-Path $RepoRoot "analysis\local\SCUS_971.77.identity.json"
$environmentReport = Join-Path $RepoRoot "analysis\local\environment.json"
$deepReport = Join-Path $RepoRoot "analysis\local\SCUS_971.77.deep.json"
$ghidraToml = Join-Path $RepoRoot "analysis\SCUS_971.77.ghidra.toml"
$buildReport = Join-Path $DistDir "build_report.json"
$runner = Join-Path $DistDir "ps2EntryRunner.exe"
$probe = Join-Path $DistDir "first_boot_probe.json"
$triage = Join-Path $DistDir "first_boot_probe_triage.json"
$suggestions = Join-Path $DistDir "first_boot_probe_suggestions.json"

Write-Host "============================================================"
Write-Host " Recomp Domination - local status"
Write-Host "============================================================"
Write-Host ("Repo: " + $RepoRoot)
Write-Host ("Game: " + $GameRoot)
Write-Host ""

$elfOk = Test-PathBool $elf
$elfDetail = if ($elfOk) { ((Get-Item -LiteralPath $elf).Length.ToString() + " bytes") } else { "missing" }
Status-Line "SCUS_971.77" $elfOk $elfDetail

$cdRootOk = Test-PathBool $cdRootSidecar
$cdRootDetail = if ($cdRootOk) { (Get-Content -LiteralPath $cdRootSidecar -TotalCount 1) } else { "not configured" }
Status-Line "Extracted CD root" $cdRootOk $cdRootDetail

$cdImageOk = Test-PathBool $cdImageSidecar
$cdImageDetail = if ($cdImageOk) { (Get-Content -LiteralPath $cdImageSidecar -TotalCount 1) } else { "not configured" }
Status-Line "CD image" $cdImageOk $cdImageDetail

$ghidraOk = Test-PathBool $ghidraCsv
$ghidraDetail = if ($ghidraOk) { ((@(Get-Content -LiteralPath $ghidraCsv).Count - 1).ToString() + " functions") } else { "analyzer fallback" }
Status-Line "Ghidra function map" $ghidraOk $ghidraDetail

Status-Line "Environment preflight" (Test-PathBool $environmentReport) $environmentReport
Status-Line "Validated identity report" (Test-PathBool $identity) $identity
Status-Line "Deep ELF census" (Test-PathBool $deepReport) $deepReport
Status-Line "Ghidra TOML" (Test-PathBool $ghidraToml) $ghidraToml
Status-Line "Generated TOML" (Test-PathBool $config) $config
Status-Line "Native runner" (Test-PathBool $runner) $runner
Status-Line "Build report" (Test-PathBool $buildReport) $buildReport
Status-Line "90s probe metadata" (Test-PathBool $probe) $probe
Status-Line "Probe triage" (Test-PathBool $triage) $triage
Status-Line "Bring-up suggestions" (Test-PathBool $suggestions) $suggestions

if (Test-Path -LiteralPath $deepReport) {
    try {
        $deep = Get-Content -Raw -LiteralPath $deepReport | ConvertFrom-Json
        Write-Host ""
        Write-Host "Deep ELF census:" -ForegroundColor Cyan
        Write-Host ("  Scan mode:   " + $deep.scan_mode)
        if ($deep.function_csv_records -ne $null) {
            Write-Host ("  CSV records: " + $deep.function_csv_records)
        }
        Write-Host ("  Words:       " + $deep.instruction_words)
        if ($deep.families) {
            Write-Host ("  COP0:        " + $deep.families.cop0)
            Write-Host ("  COP1:        " + $deep.families.cop1)
            Write-Host ("  COP2/VU0:    " + $deep.families.cop2_vu0_macro)
            Write-Host ("  MMI:         " + $deep.families.mmi)
            Write-Host ("  JAL targets: " + $deep.families.unique_jal_targets)
        }
    } catch {
        Write-Warning ("Could not parse deep ELF report: " + $_.Exception.Message)
    }
}
if (Test-Path -LiteralPath $buildReport) {
    try {
        $build = Get-Content -Raw -LiteralPath $buildReport | ConvertFrom-Json
        Write-Host ""
        Write-Host "Last build:" -ForegroundColor Cyan
        Write-Host ("  PS2Recomp:   " + $build.ps2recomp_commit)
        Write-Host ("  Ghidra CSV:  " + $build.ghidra_map_used)
        if ($build.ghidra_toml_used -ne $null) {
            Write-Host ("  Ghidra TOML: " + $build.ghidra_toml_used)
        }
        if ($build.ghidra_imported_stubs) {
            Write-Host ("  Ghidra stubs: " + @($build.ghidra_imported_stubs).Count)
        }
        if ($build.ghidra_imported_untracked_stubs) {
            Write-Host ("  Ghidra untracked: " + @($build.ghidra_imported_untracked_stubs).Count)
        }
        if ($build.patch_policy) {
            Write-Host ("  Patch policy: syscall=" + $build.patch_policy.patch_syscalls +
                        " cop0=" + $build.patch_policy.patch_cop0 +
                        " cache=" + $build.patch_policy.patch_cache)
        }
        if ($build.metrics) {
            Write-Host ("  Output mode: " + $build.metrics.output_mode)
            Write-Host ("  Functions:   " + $build.metrics.generated_function_declarations)
            Write-Host ("  Stubs:       " + $build.metrics.generated_stub_declarations)
            Write-Host ("  TODO_NAMED:  " + $build.metrics.todo_named_occurrences)
            Write-Host ("  Runner SHA:  " + $build.metrics.runner_sha256)
        }
    } catch {
        Write-Warning ("Could not parse build_report.json: " + $_.Exception.Message)
    }
}

if (Test-Path -LiteralPath $probe) {
    try {
        $p = Get-Content -Raw -LiteralPath $probe | ConvertFrom-Json
        Write-Host ""
        Write-Host "Last bounded probe:" -ForegroundColor Cyan
        Write-Host ("  Timed out: " + $p.timed_out)
        Write-Host ("  Exit code: " + $p.exit_code)
        Write-Host ("  Duration:  " + $p.duration_seconds + " s")
        Write-Host ("  STDOUT:    " + $p.stdout_bytes + " bytes")
        Write-Host ("  STDERR:    " + $p.stderr_bytes + " bytes")
    } catch {
        Write-Warning ("Could not parse first_boot_probe.json: " + $_.Exception.Message)
    }
}

Write-Host ""
if (!$elfOk) {
    Write-Host "Next: place SCUS_971.77 in the game root." -ForegroundColor Yellow
} elseif (!$cdRootOk -and !$cdImageOk) {
    Write-Host "Next: run PREPARE_GAME_DATA.cmd." -ForegroundColor Yellow
} elseif (!(Test-Path -LiteralPath $runner)) {
    Write-Host "Next: run BUILD_DOWNHILL.cmd (or BUILD_DOWNHILL_MULTIFILE.cmd)." -ForegroundColor Yellow
} elseif (!(Test-Path -LiteralPath $probe)) {
    Write-Host "Next: run DownhillRecompiled\RUN_PROBE_90S.cmd." -ForegroundColor Yellow
} else {
    Write-Host "Build/probe artifacts exist. Review triage/suggestions or run COLLECT_DIAGNOSTICS.cmd." -ForegroundColor Green
}
