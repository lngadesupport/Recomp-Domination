param(
    [Parameter(Mandatory=$true)][string]$Suggestions,
    [string]$Triage = "",
    [string]$Existing = "",
    [Parameter(Mandatory=$true)][string]$Out
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$Suggestions=(Resolve-Path -LiteralPath $Suggestions).Path
$data=Get-Content -Raw -LiteralPath $Suggestions | ConvertFrom-Json
$triageData=$null
if($Triage -and (Test-Path -LiteralPath $Triage)){
    $triageData=Get-Content -Raw -LiteralPath $Triage | ConvertFrom-Json
}

$blocked=$false
$reason='eligible'
$primary=if($triageData -and $triageData.primary_classification){[string]$triageData.primary_classification}else{'unknown'}

if($primary -in @('fatal-or-exception','unsupported-instruction')){
    $blocked=$true
    $reason='triage-blocker-' + $primary
}

$existingSet=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
if($Existing -and (Test-Path -LiteralPath $Existing)){
    foreach($line in Get-Content -LiteralPath $Existing){
        $v=$line.Trim()
        if($v -match '^0x[0-9A-Fa-f]{8}$'){[void]$existingSet.Add($v)}
    }
}

$selected=New-Object System.Collections.Generic.List[string]
$rejected=New-Object System.Collections.Generic.List[object]
foreach($value in @($data.new_entry_point_candidates)){
    $v=[string]$value
    $why=$null
    if($v -notmatch '^0x([0-9A-Fa-f]{8})$'){$why='invalid-format'}
    else{
        [uint32]$pc=[Convert]::ToUInt32($Matches[1],16)
        if($pc -lt [uint32]0x0010A000 -or $pc -ge [uint32]0x0029DCF0){$why='outside-file-backed-range'}
        elseif(($pc -band 3)-ne 0){$why='unaligned'}
        elseif($existingSet.Contains(('0x{0:X8}' -f $pc))){$why='already-configured'}
        elseif($blocked){$why=$reason}
        else{$selected.Add(('0x{0:X8}' -f $pc))}
    }
    if($why){$rejected.Add([pscustomobject]@{address=$v;reason=$why})}
}

$selected=@($selected|Sort-Object -Unique)
$report=[ordered]@{
    suggestions=$Suggestions
    triage=if($Triage){[IO.Path]::GetFullPath($Triage)}else{$null}
    primary_classification=$primary
    blocked=$blocked
    reason=$reason
    selected=$selected
    selected_count=$selected.Count
    rejected=@($rejected)
}
[IO.File]::WriteAllText([IO.Path]::GetFullPath($Out),($report|ConvertTo-Json -Depth 6),(New-Object Text.UTF8Encoding($false)))
Write-Host ('Auto-entry selection: selected={0}, blocked={1}, primary={2}' -f $selected.Count,$blocked,$primary)
foreach($v in $selected){Write-Host ('  '+$v) -ForegroundColor Green}
if($blocked){exit 3}
exit 0
