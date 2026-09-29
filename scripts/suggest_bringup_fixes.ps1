param(
    [Parameter(Mandatory=$true)][string]$Log,
    [string]$Config = "",
    [string]$Out = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Log = (Resolve-Path -LiteralPath $Log).Path
if (!$Out) { $Out = Join-Path (Split-Path $Log -Parent) "first_boot_suggestions.json" }

$text = Get-Content -Raw -LiteralPath $Log
$lines = @(Get-Content -LiteralPath $Log)

$existing = New-Object 'System.Collections.Generic.HashSet[uint32]'
if ($Config -and (Test-Path -LiteralPath $Config)) {
    $cfg = Get-Content -Raw -LiteralPath $Config
    $m = [regex]::Match($cfg,'(?ms)^entry_points\s*=\s*\[(.*?)^\s*\]')
    if ($m.Success) {
        foreach ($a in [regex]::Matches($m.Groups[1].Value,'0x([0-9A-Fa-f]{1,8})')) {
            [void]$existing.Add([Convert]::ToUInt32($a.Groups[1].Value,16))
        }
    }
}

$candidateCounts = @{}
$candidateLines = @{}
foreach ($line in $lines) {
    $m = [regex]::Match($line,'(?i)No exact recompiled function for guest PC 0x([0-9a-f]{1,8})')
    if (!$m.Success) { continue }
    [uint32]$pc = [Convert]::ToUInt32($m.Groups[1].Value,16)
    # The validated retail ELF registers only its file-backed PF_X payload as code.
    if ($pc -lt [uint32]0x0010A000 -or $pc -ge [uint32]0x0029DCF0 -or (($pc -band 3) -ne 0)) { continue }
    if (!$candidateCounts.ContainsKey($pc)) { $candidateCounts[$pc]=0; $candidateLines[$pc]=$line }
    $candidateCounts[$pc]++
}

$candidates = @(
    $candidateCounts.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object {
        [uint32]$pc=[uint32]$_.Key
        [ordered]@{
            address=('0x{0:X8}' -f $pc)
            occurrences=[int]$_.Value
            already_configured=$existing.Contains($pc)
            first_log_line=$candidateLines[$pc]
        }
    }
)

$stubCounts=@{}
foreach($line in $lines){
    $name=$null
    $m=[regex]::Match($line,'(?i)Unimplemented PS2 stub called\.\s*name=([^,\s]+)')
    if($m.Success){$name=$m.Groups[1].Value}
    if(!$name){
        $m=[regex]::Match($line,'(?i)Unimplemented PS2 stub called:\s*([^\s]+)')
        if($m.Success){$name=$m.Groups[1].Value}
    }
    if($name){if(!$stubCounts.ContainsKey($name)){$stubCounts[$name]=0};$stubCounts[$name]++}
}
$stubs=@($stubCounts.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { [ordered]@{name=$_.Key;occurrences=[int]$_.Value} })

$newEntries=@($candidates | Where-Object { -not $_.already_configured } | ForEach-Object {$_.address})
$snippet = if($newEntries.Count -gt 0){
    "# Suggested only; review before adding.`r`n" + ($newEntries | ForEach-Object {'  "'+$_+'",'} | Out-String)
} else { "# No new file-backed EE entry point candidates were found." }

$report=[ordered]@{
    source_log=$Log
    config=if($Config){[IO.Path]::GetFullPath($Config)}else{$null}
    executable_file_backed_range=[ordered]@{start='0x0010A000';end_exclusive='0x0029DCF0'}
    missing_function_candidates=$candidates
    new_entry_point_candidates=$newEntries
    unimplemented_stubs=$stubs
    toml_snippet=$snippet.TrimEnd()
}

[IO.File]::WriteAllText([IO.Path]::GetFullPath($Out),($report|ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))
Write-Host "Bring-up suggestions: $Out"
if($newEntries.Count -gt 0){Write-Host ("New entry-point candidates: "+($newEntries -join ', ')) -ForegroundColor Yellow}
if($stubs.Count -gt 0){Write-Host ("Unimplemented stubs observed: "+(($stubs|ForEach-Object {$_.name}) -join ', ')) -ForegroundColor Yellow}
