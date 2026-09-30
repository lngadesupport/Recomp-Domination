param(
    [Parameter(Mandatory=$true)][string]$Log,
    [string]$Out = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Log = (Resolve-Path -LiteralPath $Log).Path
if (!$Out) {
    $Out = Join-Path (Split-Path $Log -Parent) "first_boot_triage.json"
}

$lines = @(Get-Content -LiteralPath $Log -ErrorAction Stop)
$text = $lines -join [Environment]::NewLine

$iopModules = [ordered]@{
    loaded_irx = @()
    hle_fallbacks = @()
    load_failures = @()
    failed_open = @()
    relocation_warnings = 0
    unhandled_imports = @()
}

foreach($line in $lines){
    $loaded=[regex]::Match($line,'(?i)\[IOP\]\s+loaded IRX\s+id=(\d+)\s+entry=(0x[0-9a-f]+)\s+base=(0x[0-9a-f]+)\s+start=(-?\d+)')
    if($loaded.Success){
        $iopModules.loaded_irx += [pscustomobject][ordered]@{
            id=[int]$loaded.Groups[1].Value
            entry=$loaded.Groups[2].Value.ToUpperInvariant()
            base=$loaded.Groups[3].Value.ToUpperInvariant()
            start_result=[int]$loaded.Groups[4].Value
        }
        continue
    }

    $hle=[regex]::Match($line,"(?i)\[IOP:HLE\]\s+fallback module='([^']+)'")
    if($hle.Success){
        $iopModules.hle_fallbacks += $hle.Groups[1].Value
        continue
    }

    $failed=[regex]::Match($line,"(?i)\[IOP:load-failed\]\s+module='([^']+)'")
    if($failed.Success){
        $iopModules.load_failures += $failed.Groups[1].Value
        continue
    }

    $openFailed=[regex]::Match($line,"(?i)\[IOP\]\s+failed to open IRX\s+'([^']+)'")
    if($openFailed.Success){
        $iopModules.failed_open += $openFailed.Groups[1].Value
        continue
    }

    if($line -match '(?i)one or more IRX relocations were unsupported'){
        $iopModules.relocation_warnings++
        continue
    }

    $unhandled=[regex]::Match($line,'(?i)\[IOP\]\s+unhandled import\s+([^:\s]+):(\d+)\s+version=(0x[0-9a-f]+)\s+pc=(0x[0-9a-f]+)')
    if($unhandled.Success){
        $iopModules.unhandled_imports += [pscustomobject][ordered]@{
            library=$unhandled.Groups[1].Value
            ordinal=[int]$unhandled.Groups[2].Value
            version=$unhandled.Groups[3].Value.ToUpperInvariant()
            pc=$unhandled.Groups[4].Value.ToUpperInvariant()
        }
    }
}

$iopModules.hle_fallbacks=@($iopModules.hle_fallbacks|Sort-Object -Unique)
$iopModules.load_failures=@($iopModules.load_failures|Sort-Object -Unique)
$iopModules.failed_open=@($iopModules.failed_open|Sort-Object -Unique)

$rpcDiagnostics = [ordered]@{
    unhandled_calls = @()
}

foreach($line in $lines){
    $rpc=[regex]::Match(
        $line,
        '(?i)\[IOP/RPC trace:unhandled\]\s+sid=(0x[0-9a-f]+)\s+rpc=(0x[0-9a-f]+)\s+pc=(0x[0-9a-f]+)\s+ra=(0x[0-9a-f]+)\s+send=(0x[0-9a-f]+)/([0-9]+)\s+recv=(0x[0-9a-f]+)/([0-9]+).*?loadedModules=\[(.*?)\]'
    )
    if($rpc.Success){
        $rpcDiagnostics.unhandled_calls += [pscustomobject][ordered]@{
            sid=$rpc.Groups[1].Value.ToUpperInvariant()
            rpc=$rpc.Groups[2].Value.ToUpperInvariant()
            pc=$rpc.Groups[3].Value.ToUpperInvariant()
            ra=$rpc.Groups[4].Value.ToUpperInvariant()
            send_buffer=$rpc.Groups[5].Value.ToUpperInvariant()
            send_size=[int]$rpc.Groups[6].Value
            recv_buffer=$rpc.Groups[7].Value.ToUpperInvariant()
            recv_size=[int]$rpc.Groups[8].Value
            loaded_modules=$rpc.Groups[9].Value
        }
    }
}

$mpegDiagnostics = [ordered]@{
    no_ffmpeg = $false
    feed_events = 0
    picture_waits = 0
    is_end_checks = 0
    errors = @()
}

foreach($line in $lines){
    if($line -match '(?i)\[MPEG\]\s+runtime built without FFmpeg'){
        $mpegDiagnostics.no_ffmpeg = $true
    }
    if($line -match '(?i)\[MPEG:feedES\]'){
        $mpegDiagnostics.feed_events++
    }
    if($line -match '(?i)\[MPEG:GetPicture\]\s+waiting'){
        $mpegDiagnostics.picture_waits++
    }
    if($line -match '(?i)\[MPEG:IsEnd\]'){
        $mpegDiagnostics.is_end_checks++
    }
    if($line -match '(?i)\[MPEG\].*(failed|error)'){
        $mpegDiagnostics.errors += $line.Trim()
    }
}
$mpegDiagnostics.errors=@($mpegDiagnostics.errors|Select-Object -Unique|Select-Object -First 32)

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
$fileIoDiagnostics=[ordered]@{
    open_failures=$fileIoFailures
    total_failures=[int](@($fileIoFailures|ForEach-Object{$_.occurrences})|Measure-Object -Sum).Sum
    repeated_paths=@($fileIoFailures|Where-Object{$_.repeated}|ForEach-Object{$_.path})
}

$categories = [ordered]@{
    fatal_or_exception = @($lines | Where-Object { $_ -match '(?i)fatal|exception|terminate|abort|assert' }).Count
    missing_function = @($lines | Where-Object { $_ -match '(?i)function.+not found|missing.+function|lookupFunction|unresolved.+function' }).Count
    todo_or_stub = @($lines | Where-Object { $_ -match '(?i)TODO_NAMED|\bTODO\b|unimplemented.+stub|stub.+unimplemented' }).Count
    unsupported_instruction = @($lines | Where-Object { $_ -match '(?i)unhandled.+instruction|unsupported.+instruction|reserved instruction|unknown opcode' }).Count
    sif_iop_rpc = @($lines | Where-Object { $_ -match '(?i)\bSIF\b|\bIOP\b|\bRPC\b|sceSif|SifCallRpc' }).Count
    vif_vu_gs = @($lines | Where-Object { $_ -match '(?i)\bVIF[01]?\b|\bVU[01]?\b|\bGIF\b|\bGS\b|DMAC' }).Count
    file_io = @($lines | Where-Object { $_ -match '(?i)fio(Open|Read|Lseek|Close)|cdrom|host:|file.+not found' }).Count
    pad = @($lines | Where-Object { $_ -match '(?i)scePad|padread|gamepad' }).Count
    iop_loaded_irx = @($iopModules.loaded_irx).Count
    iop_hle_fallback = @($iopModules.hle_fallbacks).Count
    iop_load_failed = @($iopModules.load_failures).Count
    iop_failed_open = @($iopModules.failed_open).Count
    iop_unhandled_import = @($iopModules.unhandled_imports).Count
    iop_rpc_unhandled = @($rpcDiagnostics.unhandled_calls).Count
    mpeg_no_ffmpeg = if($mpegDiagnostics.no_ffmpeg){1}else{0}
    mpeg_picture_wait = $mpegDiagnostics.picture_waits
    mpeg_error = @($mpegDiagnostics.errors).Count
    file_open_failed = $fileIoDiagnostics.total_failures
    file_open_repeated = @($fileIoDiagnostics.repeated_paths).Count
}

$runtimeCounters = [ordered]@{
    tick_samples = 0
    max_active_threads = 0
    max_dma = 0
    max_gif = 0
    max_gs_writes = 0
    max_vif = 0
    last_pc = $null
    last_ra = $null
    last_dispfb1 = $null
    last_display1 = $null
    display_registers_programmed = $false
}
foreach($line in $lines){
    $tickMatch=[regex]::Match(
        $line,
        '(?i)\[run:tick\].*?\bpc=(0x[0-9a-f]+).*?\bra=(0x[0-9a-f]+).*?\bdispfb1=(0x[0-9a-f]+).*?\bdisplay1=(0x[0-9a-f]+).*?\bactiveThreads=(\d+).*?\bdma=(\d+).*?\bgif=(\d+).*?\bgsw=(\d+).*?\bvif=(\d+)'
    )
    if(!$tickMatch.Success){continue}

    $runtimeCounters.tick_samples++
    $runtimeCounters.last_pc=$tickMatch.Groups[1].Value.ToUpperInvariant()
    $runtimeCounters.last_ra=$tickMatch.Groups[2].Value.ToUpperInvariant()
    $runtimeCounters.last_dispfb1=$tickMatch.Groups[3].Value.ToUpperInvariant()
    $runtimeCounters.last_display1=$tickMatch.Groups[4].Value.ToUpperInvariant()

    $threads=[uint64]$tickMatch.Groups[5].Value
    $dma=[uint64]$tickMatch.Groups[6].Value
    $gif=[uint64]$tickMatch.Groups[7].Value
    $gsw=[uint64]$tickMatch.Groups[8].Value
    $vif=[uint64]$tickMatch.Groups[9].Value

    if($threads -gt $runtimeCounters.max_active_threads){$runtimeCounters.max_active_threads=$threads}
    if($dma -gt $runtimeCounters.max_dma){$runtimeCounters.max_dma=$dma}
    if($gif -gt $runtimeCounters.max_gif){$runtimeCounters.max_gif=$gif}
    if($gsw -gt $runtimeCounters.max_gs_writes){$runtimeCounters.max_gs_writes=$gsw}
    if($vif -gt $runtimeCounters.max_vif){$runtimeCounters.max_vif=$vif}

    if($runtimeCounters.last_dispfb1 -ne '0X0' -and
       $runtimeCounters.last_dispfb1 -ne '0X00000000' -and
       $runtimeCounters.last_display1 -ne '0X0' -and
       $runtimeCounters.last_display1 -ne '0X00000000'){
        $runtimeCounters.display_registers_programmed=$true
    }
}

$milestones = [ordered]@{
    elf_loaded = [regex]::IsMatch($text,'(?i)ELF file loaded successfully|Entry point:\s*0x0010A008|0010A008.*enter')
    main_reached = [regex]::IsMatch($text,'(?i)\bmain\b.*enter|001FB6C0')
    sif_iop_activity = ($categories.sif_iop_rpc -gt 0)
    iop_module_activity = (@($iopModules.loaded_irx).Count -gt 0 -or @($iopModules.hle_fallbacks).Count -gt 0)
    pad_activity = ($categories.pad -gt 0)
    vif_vu_activity = [regex]::IsMatch($text,'(?i)\bVIF[01]?\b|\bVU[01]?\b|MSCALF?|MSCNT')
    gif_gs_activity = [regex]::IsMatch($text,'(?i)\bGIF\b|\bGS\b|GifArbiter|processGIFPacket')
    vif_writes_seen = ([uint64]$runtimeCounters.max_vif -gt 0)
    gif_packets_seen = ([uint64]$runtimeCounters.max_gif -gt 0)
    gs_writes_seen = ([uint64]$runtimeCounters.max_gs_writes -gt 0)
    display_registers_programmed = [bool]$runtimeCounters.display_registers_programmed
    guest_graphics_activity = ([uint64]$runtimeCounters.max_gif -gt 0 -or [uint64]$runtimeCounters.max_gs_writes -gt 0)
}

$graphicsStage = "none"
if([uint64]$runtimeCounters.max_vif -gt 0){$graphicsStage="vif"}
if([uint64]$runtimeCounters.max_gif -gt 0){$graphicsStage="gif"}
if([uint64]$runtimeCounters.max_gs_writes -gt 0){$graphicsStage="gs-writes"}
if([bool]$runtimeCounters.display_registers_programmed){$graphicsStage="display-configured"}

$furthestMilestone = "none"
foreach($candidate in @(
    [pscustomobject]@{name="elf-loaded";hit=[bool]$milestones.elf_loaded},
    [pscustomobject]@{name="main";hit=[bool]$milestones.main_reached},
    [pscustomobject]@{name="sif-iop";hit=[bool]$milestones.sif_iop_activity},
    [pscustomobject]@{name="pad";hit=[bool]$milestones.pad_activity},
    [pscustomobject]@{name="vif-vu";hit=[bool]$milestones.vif_vu_activity},
    [pscustomobject]@{name="gif-gs";hit=[bool]$milestones.gif_gs_activity},
    [pscustomobject]@{name="guest-graphics";hit=[bool]$milestones.guest_graphics_activity}
)){
    if($candidate.hit){$furthestMilestone=$candidate.name}
}

$knownAddressHits = [ordered]@{}
foreach($knownPc in @("0010A008","001FB6C0","00254050","0025C440")){
    $knownAddressHits["0x" + $knownPc] = ([regex]::Matches($text,'(?i)(?:0x)?'+$knownPc)).Count
}

$pcMatches = [regex]::Matches($text, '(?i)(?:\bpc\b|\bra\b)\s*[=:]\s*(0x[0-9a-f]{6,8})')
$pcs = @{}
foreach ($m in $pcMatches) {
    $pc = $m.Groups[1].Value.ToUpperInvariant()
    if (!$pcs.ContainsKey($pc)) { $pcs[$pc] = 0 }
    $pcs[$pc]++
}
$topPcs = @(
    $pcs.GetEnumerator() |
        Sort-Object Value -Descending |
        Select-Object -First 32 |
        ForEach-Object { [pscustomobject][ordered]@{ address = [string]$_.Key; count = [int]$_.Value } }
)

$firstFatal = $lines | Where-Object { $_ -match '(?i)fatal|exception|terminate|abort|assert' } | Select-Object -First 1
$firstMissing = $lines | Where-Object { $_ -match '(?i)function.+not found|missing.+function|lookupFunction|unresolved.+function' } | Select-Object -First 1
$firstTodo = $lines | Where-Object { $_ -match '(?i)TODO_NAMED|\bTODO\b|unimplemented.+stub|stub.+unimplemented' } | Select-Object -First 1
$firstInstruction = $lines | Where-Object { $_ -match '(?i)unhandled.+instruction|unsupported.+instruction|reserved instruction|unknown opcode' } | Select-Object -First 1

$primary = "no-obvious-fatal-marker"
if ($categories.fatal_or_exception -gt 0) { $primary = "fatal-or-exception" }
elseif ($categories.missing_function -gt 0) { $primary = "missing-function" }
elseif ($categories.unsupported_instruction -gt 0) { $primary = "unsupported-instruction" }
elseif ($categories.todo_or_stub -gt 0) { $primary = "todo-or-stub" }
elseif ($categories.iop_load_failed -gt 0 -or $categories.iop_failed_open -gt 0) { $primary = "iop-module-load" }
elseif ($categories.iop_unhandled_import -gt 0) { $primary = "iop-unhandled-import" }
elseif ($categories.iop_rpc_unhandled -gt 0) { $primary = "iop-rpc-unhandled" }
elseif ($categories.mpeg_error -gt 0) { $primary = "mpeg-error" }
elseif ($categories.mpeg_no_ffmpeg -gt 0 -and $categories.mpeg_picture_wait -gt 0) { $primary = "mpeg-no-ffmpeg" }
elseif ($fileIoDiagnostics.total_failures -ge 3 -and @($fileIoDiagnostics.repeated_paths).Count -gt 0) { $primary = "file-io" }
elseif ($categories.sif_iop_rpc -gt 0) { $primary = "sif-iop-rpc" }
elseif ($categories.vif_vu_gs -gt 0) { $primary = "vif-vu-gs" }

$tailCount = [Math]::Min(120, $lines.Count)
$tail = if ($tailCount -gt 0) { @($lines | Select-Object -Last $tailCount) } else { @() }

$report = [pscustomobject][ordered]@{
    source_log = $Log
    line_count = $lines.Count
    primary_classification = $primary
    categories = [pscustomobject]$categories
    milestones = [pscustomobject]$milestones
    runtime_counters = [pscustomobject]$runtimeCounters
    iop_modules = [pscustomobject]$iopModules
    rpc = [pscustomobject]$rpcDiagnostics
    mpeg = [pscustomobject]$mpegDiagnostics
    file_io = [pscustomobject]$fileIoDiagnostics
    graphics_stage = $graphicsStage
    furthest_milestone = $furthestMilestone
    known_address_hits = [pscustomobject]$knownAddressHits
    first_markers = [pscustomobject][ordered]@{
        fatal_or_exception = if($null -ne $firstFatal){[string]$firstFatal}else{$null}
        missing_function = if($null -ne $firstMissing){[string]$firstMissing}else{$null}
        todo_or_stub = if($null -ne $firstTodo){[string]$firstTodo}else{$null}
        unsupported_instruction = if($null -ne $firstInstruction){[string]$firstInstruction}else{$null}
    }
    frequent_pc_or_ra = $topPcs
    tail = @($tail | ForEach-Object { [string]$_ })
}

$json = $report | ConvertTo-Json -Depth 8
[IO.File]::WriteAllText([IO.Path]::GetFullPath($Out), $json, (New-Object Text.UTF8Encoding($false)))
Write-Host "Triage written to: $Out"
Write-Host "Primary classification: $primary"
Write-Host "Furthest boot milestone: $furthestMilestone"
Write-Host "Graphics stage: $graphicsStage"
Write-Host ("IOP modules: loaded={0}, HLE={1}, load-failed={2}, open-failed={3}, imports={4}, RPC={5}" -f @($iopModules.loaded_irx).Count,@($iopModules.hle_fallbacks).Count,@($iopModules.load_failures).Count,@($iopModules.failed_open).Count,@($iopModules.unhandled_imports).Count,@($rpcDiagnostics.unhandled_calls).Count)
Write-Host ("MPEG: no-ffmpeg={0}, feeds={1}, waits={2}, isEnd={3}, errors={4}" -f $mpegDiagnostics.no_ffmpeg,$mpegDiagnostics.feed_events,$mpegDiagnostics.picture_waits,$mpegDiagnostics.is_end_checks,@($mpegDiagnostics.errors).Count)
Write-Host ("FileIO open failures: total={0}, repeated paths={1}" -f $fileIoDiagnostics.total_failures,@($fileIoDiagnostics.repeated_paths).Count)
