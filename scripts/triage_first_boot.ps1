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

$categories = [ordered]@{
    fatal_or_exception = @($lines | Where-Object { $_ -match '(?i)fatal|exception|terminate|abort|assert' }).Count
    missing_function = @($lines | Where-Object { $_ -match '(?i)function.+not found|missing.+function|lookupFunction|unresolved.+function' }).Count
    todo_or_stub = @($lines | Where-Object { $_ -match '(?i)TODO_NAMED|\bTODO\b|unimplemented.+stub|stub.+unimplemented' }).Count
    unsupported_instruction = @($lines | Where-Object { $_ -match '(?i)unhandled.+instruction|unsupported.+instruction|reserved instruction|unknown opcode' }).Count
    sif_iop_rpc = @($lines | Where-Object { $_ -match '(?i)\bSIF\b|\bIOP\b|\bRPC\b|sceSif|SifCallRpc' }).Count
    vif_vu_gs = @($lines | Where-Object { $_ -match '(?i)\bVIF[01]?\b|\bVU[01]?\b|\bGIF\b|\bGS\b|DMAC' }).Count
    file_io = @($lines | Where-Object { $_ -match '(?i)fio(Open|Read|Lseek|Close)|cdrom|host:|file.+not found' }).Count
    pad = @($lines | Where-Object { $_ -match '(?i)scePad|padread|gamepad' }).Count
}

$runtimeCounters = [ordered]@{
    tick_samples = 0
    max_dma = 0
    max_gif = 0
    max_gs_writes = 0
    max_vif = 0
}
foreach($line in $lines){
    $tickMatch=[regex]::Match($line,'(?i)\[run:tick\].*?\bdma=(\d+).*?\bgif=(\d+).*?\bgsw=(\d+).*?\bvif=(\d+)')
    if(!$tickMatch.Success){continue}
    $runtimeCounters.tick_samples++
    $dma=[uint64]$tickMatch.Groups[1].Value
    $gif=[uint64]$tickMatch.Groups[2].Value
    $gsw=[uint64]$tickMatch.Groups[3].Value
    $vif=[uint64]$tickMatch.Groups[4].Value
    if($dma -gt $runtimeCounters.max_dma){$runtimeCounters.max_dma=$dma}
    if($gif -gt $runtimeCounters.max_gif){$runtimeCounters.max_gif=$gif}
    if($gsw -gt $runtimeCounters.max_gs_writes){$runtimeCounters.max_gs_writes=$gsw}
    if($vif -gt $runtimeCounters.max_vif){$runtimeCounters.max_vif=$vif}
}

$milestones = [ordered]@{
    elf_loaded = [regex]::IsMatch($text,'(?i)ELF file loaded successfully|Entry point:\s*0x0010A008|0010A008.*enter')
    main_reached = [regex]::IsMatch($text,'(?i)\bmain\b.*enter|001FB6C0')
    sif_iop_activity = ($categories.sif_iop_rpc -gt 0)
    pad_activity = ($categories.pad -gt 0)
    vif_vu_activity = [regex]::IsMatch($text,'(?i)\bVIF[01]?\b|\bVU[01]?\b|MSCALF?|MSCNT')
    gif_gs_activity = [regex]::IsMatch($text,'(?i)\bGIF\b|\bGS\b|GifArbiter|processGIFPacket')
    guest_graphics_activity = ([uint64]$runtimeCounters.max_gif -gt 0 -or [uint64]$runtimeCounters.max_gs_writes -gt 0)
}

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
