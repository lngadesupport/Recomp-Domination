param(
    [Parameter(Mandatory=$true)][string]$Suggestions,
    [string]$Triage = "",
    [string]$Existing = "",
    [Parameter(Mandatory=$true)][string]$Out
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Suggestions = (Resolve-Path -LiteralPath $Suggestions).Path
$data = Get-Content -Raw -LiteralPath $Suggestions | ConvertFrom-Json

$triageData = $null
if ($Triage -and (Test-Path -LiteralPath $Triage)) {
    $triageData = Get-Content -Raw -LiteralPath $Triage | ConvertFrom-Json
}

$primary = if ($triageData -and $triageData.primary_classification) {
    [string]$triageData.primary_classification
} else {
    'unknown'
}

$blocked = $primary -in @('fatal-or-exception','unsupported-instruction')
$reason = if ($blocked) { 'triage-blocker-' + $primary } else { 'eligible' }

$existingSet = @{}
if ($Existing -and (Test-Path -LiteralPath $Existing)) {
    foreach ($line in Get-Content -LiteralPath $Existing) {
        $value = $line.Trim()
        if ($value -match '^0x[0-9A-Fa-f]{8}$') {
            $existingSet[$value.ToUpperInvariant()] = $true
        }
    }
}

$selected = @()
$rejected = @()

foreach ($candidate in @($data.new_entry_point_candidates)) {
    $value = [string]$candidate
    $why = $null

    if ($value -notmatch '^0x([0-9A-Fa-f]{8})$') {
        $why = 'invalid-format'
    }
    else {
        [uint32]$pc = [Convert]::ToUInt32($Matches[1], 16)
        $canonical = ('0x{0:X8}' -f $pc)

        if ($pc -lt [uint32]0x0010A000 -or $pc -ge [uint32]0x0029DCF0) {
            $why = 'outside-file-backed-range'
        }
        elseif (($pc -band 3) -ne 0) {
            $why = 'unaligned'
        }
        elseif ($existingSet.ContainsKey($canonical)) {
            $why = 'already-configured'
        }
        elseif ($blocked) {
            $why = $reason
        }
        else {
            $selected += $canonical
        }
    }

    if ($why) {
        $rejected += [pscustomobject][ordered]@{
            address = $value
            reason = $why
        }
    }
}

$selected = @($selected | Sort-Object -Unique)
$report = [ordered]@{
    suggestions = $Suggestions
    triage = if ($Triage) { [IO.Path]::GetFullPath($Triage) } else { $null }
    primary_classification = $primary
    blocked = $blocked
    reason = $reason
    selected = $selected
    selected_count = $selected.Count
    rejected = $rejected
}

[IO.File]::WriteAllText(
    [IO.Path]::GetFullPath($Out),
    ($report | ConvertTo-Json -Depth 6),
    (New-Object Text.UTF8Encoding($false))
)

Write-Host ('Auto-entry selection: selected={0}, blocked={1}, primary={2}' -f $selected.Count, $blocked, $primary)
foreach ($value in $selected) {
    Write-Host ('  ' + $value) -ForegroundColor Green
}

if ($blocked) { exit 3 }
exit 0
