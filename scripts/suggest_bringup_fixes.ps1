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

$existing = @{}
if ($Config -and (Test-Path -LiteralPath $Config)) {
    $cfg = Get-Content -Raw -LiteralPath $Config
    $m = [regex]::Match($cfg, '(?ms)^entry_points\s*=\s*\[(.*?)^\s*\]')
    if ($m.Success) {
        foreach ($a in [regex]::Matches($m.Groups[1].Value, '0x([0-9A-Fa-f]{1,8})')) {
            [uint32]$existingPc = [Convert]::ToUInt32($a.Groups[1].Value, 16)
            $existing[$existingPc] = $true
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
                already_configured = $existing.ContainsKey($pc)
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
    unhandled_imports = @()
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

    if($line -match '(?i)one or more IRX relocations were unsupported'){$iop.relocation_warnings++;continue}

    $m=[regex]::Match($line,'(?i)\[IOP\]\s+unhandled import\s+([^:\s]+):(\d+)\s+version=(0x[0-9a-f]+)\s+pc=(0x[0-9a-f]+)')
    if($m.Success){
        $iop.unhandled_imports += [pscustomobject][ordered]@{
            library=$m.Groups[1].Value
            ordinal=[int]$m.Groups[2].Value
            version=$m.Groups[3].Value.ToUpperInvariant()
            pc=$m.Groups[4].Value.ToUpperInvariant()
        }
    }
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
elseif(@($iop.unhandled_imports).Count -gt 0){
    $iop.focus='Physical IRX execution reached an unsupported IOP import. Implement the reported library/ordinal before changing EE entry points or graphics code.'
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

$rpc = [ordered]@{
    unhandled_calls = @()
    focus = $null
}

foreach($line in $lines){
    $m=[regex]::Match(
        $line,
        '(?i)\[IOP/RPC trace:unhandled\]\s+sid=(0x[0-9a-f]+)\s+rpc=(0x[0-9a-f]+)\s+pc=(0x[0-9a-f]+)\s+ra=(0x[0-9a-f]+)\s+send=(0x[0-9a-f]+)/([0-9]+)\s+recv=(0x[0-9a-f]+)/([0-9]+).*?loadedModules=\[(.*?)\]'
    )
    if($m.Success){
        $rpc.unhandled_calls += [pscustomobject][ordered]@{
            sid=$m.Groups[1].Value.ToUpperInvariant()
            rpc=$m.Groups[2].Value.ToUpperInvariant()
            pc=$m.Groups[3].Value.ToUpperInvariant()
            ra=$m.Groups[4].Value.ToUpperInvariant()
            send_size=[int]$m.Groups[6].Value
            recv_size=[int]$m.Groups[8].Value
            loaded_modules=$m.Groups[9].Value
        }
    }
}

if(@($rpc.unhandled_calls).Count -gt 0){
    $first=@($rpc.unhandled_calls)[0]
    $rpc.focus=('Unhandled IOP RPC SID {0} / RPC {1} at PC {2}. Verify the physical IRX/HLE server for that SID before changing EE recompilation.' -f $first.sid,$first.rpc,$first.pc)
}else{
    $rpc.focus='No unhandled IOP RPC trace was observed in the captured log.'
}

$mpeg = [ordered]@{
    no_ffmpeg = $false
    feed_events = 0
    picture_waits = 0
    is_end_checks = 0
    errors = @()
    focus = $null
}

foreach($line in $lines){
    if($line -match '(?i)\[MPEG\]\s+runtime built without FFmpeg'){
        $mpeg.no_ffmpeg = $true
    }
    if($line -match '(?i)\[MPEG:feedES\]'){$mpeg.feed_events++}
    if($line -match '(?i)\[MPEG:GetPicture\]\s+waiting'){$mpeg.picture_waits++}
    if($line -match '(?i)\[MPEG:IsEnd\]'){$mpeg.is_end_checks++}
    if($line -match '(?i)\[MPEG\].*(failed|error)'){$mpeg.errors += $line.Trim()}
}
$mpeg.errors=@($mpeg.errors|Select-Object -Unique|Select-Object -First 32)

if(@($mpeg.errors).Count -gt 0){
    $mpeg.focus='MPEG runtime reported decode/demux errors. Treat video playback as the blocker before changing EE entry points.'
}
elseif($mpeg.no_ffmpeg -and $mpeg.picture_waits -gt 0){
    $mpeg.focus='The game reached MPEG picture waits while this bring-up build has FFmpeg disabled. Keep EE entry points unchanged; either let the stream reach EOF/stub-frame fallback or use an optional FFmpeg-enabled build to validate the movie path.'
}
elseif($mpeg.no_ffmpeg -and $mpeg.feed_events -gt 0){
    $mpeg.focus='MPEG/PSS data is reaching the runtime, but FFmpeg is intentionally disabled in the baseline. Video will use the stub path; this is not evidence of a missing EE function.'
}
elseif($mpeg.feed_events -gt 0 -or $mpeg.is_end_checks -gt 0){
    $mpeg.focus='MPEG playback code is active. Use feed/GetPicture/IsEnd progression to distinguish movie-path stalls from the later menu/gameplay path.'
}
else{
    $mpeg.focus='No MPEG activity was observed in the captured log.'
}

$fileIoCounts=@{}
$fileIoFirstPc=@{}
$fileIoFlags=@{}
foreach($line in $lines){
    $m=[regex]::Match($line,"(?i)\[FileIO:open-failed\]\s+guest='([^']+)'\s+flags=(0x[0-9a-f]+)\s+pc=(0x[0-9a-f]+)")
    if(!$m.Success){continue}
    $path=$m.Groups[1].Value
    if(!$fileIoCounts.ContainsKey($path)){
        $fileIoCounts[$path]=0
        $fileIoFirstPc[$path]=$m.Groups[3].Value.ToUpperInvariant()
        $fileIoFlags[$path]=$m.Groups[2].Value.ToUpperInvariant()
    }
    $fileIoCounts[$path]++
}
$fileIoFailures=@(
    $fileIoCounts.GetEnumerator() |
        Sort-Object Value -Descending |
        ForEach-Object {
            [pscustomobject][ordered]@{
                path=[string]$_.Key
                occurrences=[int]$_.Value
                flags=$fileIoFlags[$_.Key]
                first_pc=$fileIoFirstPc[$_.Key]
                repeated=([int]$_.Value -ge 3)
            }
        }
)
$fileIo=[ordered]@{
    open_failures=$fileIoFailures
    repeated_paths=@($fileIoFailures|Where-Object{$_.repeated}|ForEach-Object{$_.path})
    focus=$null
}
if(@($fileIo.repeated_paths).Count -gt 0){
    $fileIo.focus='The same guest file path failed to open repeatedly. Verify extracted CD root / ISO mapping, case, ;1 version suffix handling and the exact guest path before changing EE entry points.'
}
elseif(@($fileIo.open_failures).Count -gt 0){
    $fileIo.focus='One or more guest file opens failed, but none repeated enough to treat as the primary blocker yet. Keep these paths visible while following the later runtime milestone.'
}
else{
    $fileIo.focus='No failed guest FileIO open was observed in the captured log.'
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
    rpc = [pscustomobject]$rpc
    mpeg = [pscustomobject]$mpeg
    file_io = [pscustomobject]$fileIo
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
Write-Host ("RPC focus: " + $rpc.focus)
Write-Host ("MPEG focus: " + $mpeg.focus)
Write-Host ("FileIO focus: " + $fileIo.focus)
