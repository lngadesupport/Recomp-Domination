param(
    [Parameter(Mandatory=$true)][string]$Log,
    [string]$Config = "",
    [string]$Out = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Log = (Resolve-Path -LiteralPath $Log).Path
if (!$Out) {
    $Out = Join-Path (Split-Path $Log -Parent) "first_boot_suggestions.json"
}

$text = Get-Content -Raw -LiteralPath $Log
$lines = @(Get-Content -LiteralPath $Log)

$existing = New-Object 'System.Collections.Generic.HashSet[uint32]'
if ($Config -and (Test-Path -LiteralPath $Config)) {
    $cfg = Get-Content -Raw -LiteralPath $Config
    $m = [regex]::Match($cfg, '(?ms)^entry_points\s*=\s*\[(.*?)^\s*\]')
    if ($m.Success) {
        foreach ($a in [regex]::Matches($m.Groups[1].Value, '0x([0-9A-Fa-f]{1,8})')) {
            [void]$existing.Add([Convert]::ToUInt32($a.Groups[1].Value, 16))
        }
    }
}

$candidateCounts = @{}
$candidateLines = @{}
foreach ($line in $lines) {
    $m = [regex]::Match($line, '(?i)No exact recompiled function for guest PC 0x([0-9a-f]{1,8})')
    if (!$m.Success) { continue }

    [uint32]$pc = [Convert]::ToUInt32($m.Groups[1].Value, 16)

    # The validated retail ELF registers only its file-backed PF_X payload as code.
    if ($pc -lt [uint32]0x0010A000 -or
        $pc -ge [uint32]0x0029DCF0 -or
        (($pc -band 3) -ne 0)) {
        continue
    }

    if (!$candidateCounts.ContainsKey($pc)) {
        $candidateCounts[$pc] = 0
        $candidateLines[$pc] = $line
    }
    $candidateCounts[$pc]++
}

$candidates = @(
    $candidateCounts.GetEnumerator() |
        Sort-Object Value -Descending |
        ForEach-Object {
            [uint32]$pc = [uint32]$_.Key
            [pscustomobject][ordered]@{
                address = ('0x{0:X8}' -f $pc)
                occurrences = [int]$_.Value
                already_configured = $existing.Contains($pc)
                first_log_line = $candidateLines[$pc]
            }
        }
)

$stubCounts = @{}
foreach ($line in $lines) {
    $name = $null

    $m = [regex]::Match($line, '(?i)Unimplemented PS2 stub called\.\s*name=([^,\s]+)')
    if ($m.Success) {
        $name = $m.Groups[1].Value
    }

    if (!$name) {
        $m = [regex]::Match($line, '(?i)Unimplemented PS2 stub called:\s*([^\s]+)')
        if ($m.Success) {
            $name = $m.Groups[1].Value
        }
    }

    if ($name) {
        if (!$stubCounts.ContainsKey($name)) {
            $stubCounts[$name] = 0
        }
        $stubCounts[$name]++
    }
}

$stubs = @(
    $stubCounts.GetEnumerator() |
        Sort-Object Value -Descending |
        ForEach-Object {
            [pscustomobject][ordered]@{
                name = [string]$_.Key
                occurrences = [int]$_.Value
            }
        }
)

# Classify IOP/IRX module outcomes so first-boot failures are actionable.
$iop = [ordered]@{
    loaded_irx_count = 0
    hle_fallback_modules = @()
    load_failed_modules = @()
    failed_open_modules = @()
    relocation_warnings = 0
    focus = $null
}

foreach($line in $lines){
    if($line -match '(?i)\[IOP\]\s+loaded IRX\s+id='){
        $iop.loaded_irx_count++
        continue
    }

    $m=[regex]::Match($line,"(?i)\[IOP:HLE\]\s+fallback module='([^']+)'")
    if($m.Success){$iop.hle_fallback_modules += $m.Groups[1].Value;continue}

    $m=[regex]::Match($line,"(?i)\[IOP:load-failed\]\s+module='([^']+)'")
    if($m.Success){$iop.load_failed_modules += $m.Groups[1].Value;continue}

    $m=[regex]::Match($line,"(?i)\[IOP\]\s+failed to open IRX\s+'([^']+)'")
    if($m.Success){$iop.failed_open_modules += $m.Groups[1].Value;continue}

    if($line -match '(?i)one or more IRX relocations were unsupported'){$iop.relocation_warnings++}
}
$iop.hle_fallback_modules=@($iop.hle_fallback_modules|Sort-Object -Unique)
$iop.load_failed_modules=@($iop.load_failed_modules|Sort-Object -Unique)
$iop.failed_open_modules=@($iop.failed_open_modules|Sort-Object -Unique)

if(@($iop.failed_open_modules).Count -gt 0){
    $iop.focus='Physical IRX files could not be opened. Verify CD root / ISO mapping and exact module paths before changing EE recompilation.'
}
elseif(@($iop.load_failed_modules).Count -gt 0){
    $iop.focus='One or more IOP modules could not load and had no HLE fallback. Prioritize IRX loader/import/hardware support for these modules.'
}
elseif($iop.relocation_warnings -gt 0){
    $iop.focus='Physical IRX code loaded with unsupported relocations. Inspect IOP relocation support before treating later RPC failures as EE issues.'
}
elseif($iop.loaded_irx_count -gt 0){
    $iop.focus='Physical IRX execution is active. Use later RPC/SIF or graphics milestones to identify the next blocker.'
}
elseif(@($iop.hle_fallback_modules).Count -gt 0){
    $iop.focus='IOP services are currently using HLE fallback modules. Confirm the fallback covers the game-visible RPC ABI.'
}
else{
    $iop.focus='No explicit IRX load outcome was observed in the captured log.'
}

# Infer how far guest graphics progressed from aggressive runtime tick counters.
$graphics = [ordered]@{
    max_dma = [uint64]0
    max_vif = [uint64]0
    max_gif = [uint64]0
    max_gs_writes = [uint64]0
    display_registers_programmed = $false
    stage = "none"
    focus = $null
}

foreach ($line in $lines) {
    $m = [regex]::Match(
        $line,
        '(?i)\[run:tick\].*?\bdispfb1=(0x[0-9a-f]+).*?\bdisplay1=(0x[0-9a-f]+).*?\bdma=(\d+).*?\bgif=(\d+).*?\bgsw=(\d+).*?\bvif=(\d+)'
    )

    if (!$m.Success) { continue }

    [uint64]$dma = [uint64]$m.Groups[3].Value
    [uint64]$gif = [uint64]$m.Groups[4].Value
    [uint64]$gsw = [uint64]$m.Groups[5].Value
    [uint64]$vif = [uint64]$m.Groups[6].Value

    if ($dma -gt $graphics.max_dma) { $graphics.max_dma = $dma }
    if ($vif -gt $graphics.max_vif) { $graphics.max_vif = $vif }
    if ($gif -gt $graphics.max_gif) { $graphics.max_gif = $gif }
    if ($gsw -gt $graphics.max_gs_writes) { $graphics.max_gs_writes = $gsw }

    $dispfb = $m.Groups[1].Value
    $display = $m.Groups[2].Value
    if ($dispfb -notmatch '(?i)^0x0+$' -and
        $display -notmatch '(?i)^0x0+$') {
        $graphics.display_registers_programmed = $true
    }
}

if ([uint64]$graphics.max_vif -gt 0) { $graphics.stage = "vif" }
if ([uint64]$graphics.max_gif -gt 0) { $graphics.stage = "gif" }
if ([uint64]$graphics.max_gs_writes -gt 0) { $graphics.stage = "gs-writes" }
if ([bool]$graphics.display_registers_programmed) { $graphics.stage = "display-configured" }

switch ($graphics.stage) {
    "vif" {
        $graphics.focus = "VIF traffic exists but no GIF packets were observed. Inspect VU1 MSCAL/MSCNT execution, XGKICK production and VIF1 state."
    }
    "gif" {
        $graphics.focus = "GIF traffic exists but no GS register writes were observed. Inspect GIF packet decoding/path arbitration and GS front-end submission."
    }
    "gs-writes" {
        $graphics.focus = "GS writes exist but DISPLAY1/DISPFB1 were not both programmed. Inspect display-register setup and privileged GS writes."
    }
    "display-configured" {
        $graphics.focus = "Guest graphics reached display configuration. If the window is still blank or corrupt, inspect framebuffer format, present path and GS raster output."
    }
    default {
        $graphics.focus = "No guest graphics counters advanced. Prioritize EE control flow, DMA/VIF entry points and missing functions or stubs before GS rendering."
    }
}

$newEntries = @(
    $candidates |
        Where-Object { -not $_.already_configured } |
        ForEach-Object { $_.address }
)

if ($newEntries.Count -gt 0) {
    $snippetLines = New-Object System.Collections.Generic.List[string]
    $snippetLines.Add("# Suggested only; review before adding.")
    foreach ($entry in $newEntries) {
        $snippetLines.Add(('  "{0}",' -f $entry))
    }
    $snippet = $snippetLines -join [Environment]::NewLine
}
else {
    $snippet = "# No new file-backed EE entry point candidates were found."
}

$report = [ordered]@{
    source_log = $Log
    config = if ($Config) { [IO.Path]::GetFullPath($Config) } else { $null }
    executable_file_backed_range = [ordered]@{
        start = "0x0010A000"
        end_exclusive = "0x0029DCF0"
    }
    missing_function_candidates = $candidates
    new_entry_point_candidates = $newEntries
    unimplemented_stubs = $stubs
    iop = [pscustomobject]$iop
    graphics = [pscustomobject]$graphics
    toml_snippet = $snippet
}

[IO.File]::WriteAllText(
    [IO.Path]::GetFullPath($Out),
    ($report | ConvertTo-Json -Depth 8),
    (New-Object Text.UTF8Encoding($false))
)

Write-Host "Bring-up suggestions: $Out"
if ($newEntries.Count -gt 0) {
    Write-Host ("New entry-point candidates: " + ($newEntries -join ", ")) -ForegroundColor Yellow
}
if ($stubs.Count -gt 0) {
    Write-Host ("Unimplemented stubs observed: " + (($stubs | ForEach-Object { $_.name }) -join ", ")) -ForegroundColor Yellow
}
Write-Host ("Graphics stage: " + $graphics.stage)
Write-Host ("Graphics focus: " + $graphics.focus)
Write-Host ("IOP focus: " + $iop.focus)
