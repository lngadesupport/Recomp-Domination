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
        ForEach-Object { [ordered]@{ address = $_.Key; count = $_.Value } }
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

$report = [ordered]@{
    source_log = $Log
    line_count = $lines.Count
    primary_classification = $primary
    categories = $categories
    first_markers = [ordered]@{
        fatal_or_exception = $firstFatal
        missing_function = $firstMissing
        todo_or_stub = $firstTodo
        unsupported_instruction = $firstInstruction
    }
    frequent_pc_or_ra = $topPcs
    tail = $tail
}

$json = $report | ConvertTo-Json -Depth 8
[IO.File]::WriteAllText([IO.Path]::GetFullPath($Out), $json, (New-Object Text.UTF8Encoding($false)))
Write-Host "Triage written to: $Out"
Write-Host "Primary classification: $primary"
