param(
    [string]$GameRoot = ""
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if(!$GameRoot){
    $parent=Split-Path $RepoRoot -Parent
    if(Test-Path -LiteralPath (Join-Path $parent 'DownhillRecompiled\first_boot_suggestions.json')){$GameRoot=$parent}
    elseif(Test-Path -LiteralPath 'D:\Recomp Domination\DownhillRecompiled\first_boot_suggestions.json'){$GameRoot='D:\Recomp Domination'}
    else{throw 'first_boot_suggestions.json was not found. Run the game once first or pass -GameRoot.'}
}
$GameRoot=[IO.Path]::GetFullPath($GameRoot)
$suggestionsPath=Join-Path $GameRoot 'DownhillRecompiled\first_boot_suggestions.json'
if(!(Test-Path -LiteralPath $suggestionsPath)){throw "Missing suggestions file: $suggestionsPath"}

$data=Get-Content -Raw -LiteralPath $suggestionsPath | ConvertFrom-Json
$values=@($data.new_entry_point_candidates)
if($values.Count -eq 0){Write-Host 'No new entry-point candidates to accept.';exit 0}

$accepted=New-Object System.Collections.Generic.List[string]
foreach($value in $values){
    if($value -notmatch '^0x([0-9A-Fa-f]{8})$'){continue}
    [uint32]$pc=[Convert]::ToUInt32($Matches[1],16)
    if($pc -lt [uint32]0x0010A000 -or $pc -ge [uint32]0x0029DCF0 -or (($pc -band 3)-ne 0)){continue}
    $accepted.Add(('0x{0:X8}' -f $pc))
}
$accepted=@($accepted | Sort-Object -Unique)
if($accepted.Count -eq 0){throw 'Suggestions existed, but none passed the validated executable-range/alignment checks.'}

$target=Join-Path $RepoRoot 'config\downhill.extra_entry_points.local.txt'
$existing=@()
if(Test-Path -LiteralPath $target){
    $existing=@(Get-Content -LiteralPath $target | ForEach-Object {$_.Trim()} | Where-Object {$_ -match '^0x[0-9A-Fa-f]{8}$'})
}
$merged=@($existing + $accepted | Sort-Object -Unique)
[IO.File]::WriteAllLines($target,$merged,(New-Object Text.UTF8Encoding($false)))

Write-Host 'Accepted local entry points:' -ForegroundColor Green
$accepted | ForEach-Object {Write-Host ('  '+$_)}
Write-Host ''
Write-Host ("Saved to: $target")
Write-Host 'Run BUILD_DOWNHILL.cmd again to inject them into the generated TOML.'
