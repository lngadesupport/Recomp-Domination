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
$inventoryReport = Join-Path $RepoRoot "analysis\local\game_data_inventory.json"
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

Status-Line "Game-data inventory" (Test-PathBool $inventoryReport) $inventoryReport
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

if (Test-Path -LiteralPath $inventoryReport) {
    try {
        $inventory = Get-Content -Raw -LiteralPath $inventoryReport | ConvertFrom-Json
        Write-Host ""
        Write-Host "Game-data inventory:" -ForegroundColor Cyan
        Write-Host ("  Mode:          " + $inventory.inventory_mode)
        Write-Host ("  Files:         " + $inventory.file_count)
        Write-Host ("  Total bytes:   " + $inventory.total_bytes)
        Write-Host ("  IRX files:     " + $inventory.irx_count)
        Write-Host ("  Module images: " + $inventory.module_image_count)
        if ($inventory.boot2) { Write-Host ("  BOOT2:         " + $inventory.boot2) }
        if ($inventory.irx_directories -and $inventory.irx_directories.Count -gt 0) {
            $dirs = @($inventory.irx_directories | Select-Object -First 5 | ForEach-Object { $_.directory + "=" + $_.irx_count })
            Write-Host ("  IRX dirs:      " + ($dirs -join ", "))
        }
    } catch {
        Write-Warning ("Could not parse game-data inventory: " + $_.Exception.Message)
    }
}

if (Test-Path -LiteralPath $deepReport) {
    try {
        $deep = Get-Content -Raw -LiteralPath $deepReport | ConvertFrom-Json
        Write-Host ""
        Write-Host "Deep ELF census:" -ForegroundColor Cyan
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
        Write-Host ("  PS2Recomp: " + $build.ps2recomp_commit)
        if ($build.metrics) {
            Write-Host ("  Output mode: " + $build.metrics.output_mode)
            Write-Host ("  Functions:   " + $build.metrics.generated_function_declarations)
            Write-Host ("  Stubs:       " + $build.metrics.generated_stub_declarations)
            Write-Host ("  TODO_NAMED:  " + $build.metrics.todo_named_occurrences)
            Write-Host ("  Runner SHA:  " + $build.metrics.runner_sha256)
        }
        if ($build.runtime_features) {
            Write-Host ("  FFmpeg:      " + $build.runtime_features.ffmpeg)
            Write-Host ("  RPC trace:   " + $build.runtime_features.iop_rpc_trace)
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

if (Test-Path -LiteralPath $triage) {
    try {
        $t = Get-Content -Raw -LiteralPath $triage | ConvertFrom-Json
        Write-Host ""
        Write-Host "First-boot triage:" -ForegroundColor Cyan
        Write-Host ("  Furthest milestone: " + $t.furthest_milestone)
        if ($t.graphics_stage) {
            Write-Host ("  Graphics stage:    " + $t.graphics_stage)
        }
        if ($t.runtime_counters) {
            Write-Host ("  Last PC:           " + $t.runtime_counters.last_pc)
            Write-Host ("  Last RA:           " + $t.runtime_counters.last_ra)
            Write-Host ("  Active threads:    " + $t.runtime_counters.max_active_threads)
            Write-Host ("  DMA:               " + $t.runtime_counters.max_dma)
            Write-Host ("  VIF:               " + $t.runtime_counters.max_vif)
            Write-Host ("  GIF:               " + $t.runtime_counters.max_gif)
            Write-Host ("  GS writes:         " + $t.runtime_counters.max_gs_writes)
            Write-Host ("  DISPFB1:           " + $t.runtime_counters.last_dispfb1)
            Write-Host ("  DISPLAY1:          " + $t.runtime_counters.last_display1)
        }
        if ($t.iop_modules) {
            Write-Host ("  IRX loaded:        " + @($t.iop_modules.loaded_irx).Count)
            Write-Host ("  IRX HLE fallback:  " + @($t.iop_modules.hle_fallbacks).Count)
            Write-Host ("  IRX load failed:   " + @($t.iop_modules.load_failures).Count)
            Write-Host ("  IRX open failed:   " + @($t.iop_modules.failed_open).Count)
            Write-Host ("  IRX reloc warnings:" + $t.iop_modules.relocation_warnings)
            Write-Host ("  IOP imports:       " + @($t.iop_modules.unhandled_imports).Count)
            if ($t.iop_modules.unhandled_imports -and @($t.iop_modules.unhandled_imports).Count -gt 0) {
                $firstImport = @($t.iop_modules.unhandled_imports)[0]
                Write-Host ("  First import:      {0}:{1} {2} @ {3}" -f $firstImport.library,$firstImport.ordinal,$firstImport.version,$firstImport.pc) -ForegroundColor Yellow
            }
        }
        if ($t.rpc) {
            Write-Host ("  Unhandled RPC:     " + @($t.rpc.unhandled_calls).Count)
            if ($t.rpc.unhandled_calls -and @($t.rpc.unhandled_calls).Count -gt 0) {
                $firstRpc=@($t.rpc.unhandled_calls)[0]
                Write-Host ("  First RPC:         SID {0} / {1} @ PC {2}" -f $firstRpc.sid,$firstRpc.rpc,$firstRpc.pc) -ForegroundColor Yellow
            }
        }
        if ($t.mpeg) {
            Write-Host ("  MPEG no-FFmpeg:    " + $t.mpeg.no_ffmpeg)
            Write-Host ("  MPEG feeds/waits:  {0}/{1}" -f $t.mpeg.feed_events,$t.mpeg.picture_waits)
            Write-Host ("  MPEG IsEnd/errors: {0}/{1}" -f $t.mpeg.is_end_checks,@($t.mpeg.errors).Count)
        }
        if ($t.priority_categories -and $t.priority_categories.Count -gt 0) {
            Write-Host ("  Priority:          " + (($t.priority_categories | Select-Object -First 4) -join ", "))
        }
    } catch {
        Write-Warning ("Could not parse first_boot_probe_triage.json: " + $_.Exception.Message)
    }
}

if (Test-Path -LiteralPath $suggestions) {
    try {
        $sg = Get-Content -Raw -LiteralPath $suggestions | ConvertFrom-Json
        Write-Host ""
        Write-Host "Bring-up focus:" -ForegroundColor Cyan
        if ($sg.graphics) {
            Write-Host ("  Graphics stage: " + $sg.graphics.stage)
            Write-Host ("  Focus:          " + $sg.graphics.focus)
        }
        if ($sg.iop) {
            Write-Host ("  IOP focus:      " + $sg.iop.focus)
            if ($sg.iop.load_failed_modules -and $sg.iop.load_failed_modules.Count -gt 0) {
                Write-Host ("  IOP load fail:  " + (($sg.iop.load_failed_modules | Select-Object -First 6) -join ", ")) -ForegroundColor Yellow
            }
            if ($sg.iop.failed_open_modules -and $sg.iop.failed_open_modules.Count -gt 0) {
                Write-Host ("  IOP open fail:  " + (($sg.iop.failed_open_modules | Select-Object -First 6) -join ", ")) -ForegroundColor Yellow
            }
            if ($sg.iop.unhandled_imports -and @($sg.iop.unhandled_imports).Count -gt 0) {
                $imports=@($sg.iop.unhandled_imports | Select-Object -First 4 | ForEach-Object { $_.library + ":" + $_.ordinal })
                Write-Host ("  IOP imports:    " + ($imports -join ", ")) -ForegroundColor Yellow
            }
        }
        if ($sg.rpc) {
            Write-Host ("  RPC focus:      " + $sg.rpc.focus)
            if ($sg.rpc.unhandled_calls -and @($sg.rpc.unhandled_calls).Count -gt 0) {
                $rpcRows=@($sg.rpc.unhandled_calls | Select-Object -First 4 | ForEach-Object { $_.sid + "/" + $_.rpc })
                Write-Host ("  RPC calls:      " + ($rpcRows -join ", ")) -ForegroundColor Yellow
            }
        }
        if ($sg.mpeg) {
            Write-Host ("  MPEG focus:     " + $sg.mpeg.focus)
        }
        if ($sg.new_entry_point_candidates -and $sg.new_entry_point_candidates.Count -gt 0) {
            Write-Host ("  New entries:    " + (($sg.new_entry_point_candidates | Select-Object -First 8) -join ", ")) -ForegroundColor Yellow
        }
        if ($sg.unimplemented_stubs -and $sg.unimplemented_stubs.Count -gt 0) {
            $stubNames = @($sg.unimplemented_stubs | Select-Object -First 8 | ForEach-Object { $_.name })
            Write-Host ("  TODO stubs:     " + ($stubNames -join ", ")) -ForegroundColor Yellow
        }
    } catch {
        Write-Warning ("Could not parse first_boot_probe_suggestions.json: " + $_.Exception.Message)
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
