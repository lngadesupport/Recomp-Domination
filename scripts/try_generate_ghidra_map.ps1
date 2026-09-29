param(
    [string]$GameRoot = ""
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$AnalysisDir = Join-Path $RepoRoot 'analysis'
$LocalDir = Join-Path $AnalysisDir 'local'
$Csv = Join-Path $AnalysisDir 'SCUS_971.77.functions.csv'
$Toml = Join-Path $AnalysisDir 'SCUS_971.77.ghidra.toml'
$Generator = Join-Path $RepoRoot 'scripts\generate_ghidra_map.ps1'
$StatusPath = Join-Path $LocalDir 'ghidra_optional_status.json'
New-Item -ItemType Directory -Force -Path $LocalDir | Out-Null

function Write-Status([bool]$Attempted,[bool]$Success,[string]$Reason,[string]$GhidraHome='') {
    $status=[ordered]@{
        generated_at=(Get-Date -Format o)
        attempted=$Attempted
        success=$Success
        reason=$Reason
        ghidra_home=$GhidraHome
        csv=$Csv
        toml=$Toml
    }
    [IO.File]::WriteAllText($StatusPath,($status|ConvertTo-Json -Depth 4),(New-Object Text.UTF8Encoding($false)))
}

if ((Test-Path -LiteralPath $Csv) -and (Test-Path -LiteralPath $Toml)) {
    Write-Host '      Existing Ghidra CSV/TOML found; generation skipped.' -ForegroundColor Green
    Write-Status $false $true 'existing-map'
    exit 0
}

function Find-GhidraHome {
    $candidates=New-Object System.Collections.Generic.List[string]
    if($env:GHIDRA_HOME){$candidates.Add($env:GHIDRA_HOME)}
    foreach($root in @($env:ProgramFiles,$env:USERPROFILE,(Join-Path $env:USERPROFILE 'Downloads'),'C:\')){
        if(!$root -or !(Test-Path -LiteralPath $root)){continue}
        Get-ChildItem -LiteralPath $root -Directory -Filter 'ghidra*' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            ForEach-Object {$candidates.Add($_.FullName)}
    }
    foreach($home in $candidates){
        if(Test-Path -LiteralPath (Join-Path $home 'support\analyzeHeadless.bat')){
            return [IO.Path]::GetFullPath($home)
        }
    }
    return ''
}

$ghidraHome=Find-GhidraHome
if(!$ghidraHome){
    Write-Host '      Ghidra not found; continuing with ps2_analyzer fallback.' -ForegroundColor Yellow
    Write-Status $false $true 'ghidra-not-found'
    exit 0
}

if(!(Test-Path -LiteralPath $Generator)){
    Write-Warning ('Optional Ghidra generator missing: ' + $Generator)
    Write-Status $false $false 'generator-missing' $ghidraHome
    exit 0
}

Write-Host ('      Ghidra detected at: ' + $ghidraHome) -ForegroundColor DarkGray
Write-Host '      Generating function map before recompilation...' -ForegroundColor Cyan

$args=@('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$Generator,'-GhidraHome',$ghidraHome)
if($GameRoot){$args += @('-GameRoot',$GameRoot)}

& powershell.exe @args
$rc=$LASTEXITCODE
if($rc -ne 0){
    Write-Warning ('Optional Ghidra generation failed with exit code ' + $rc + '; continuing with analyzer fallback.')
    Write-Status $true $false ('generator-exit-' + $rc) $ghidraHome
    exit 0
}

$ok=(Test-Path -LiteralPath $Csv) -and (Test-Path -LiteralPath $Toml)
if(!$ok){
    Write-Warning 'Ghidra returned success but map outputs are incomplete; continuing with analyzer fallback.'
    Write-Status $true $false 'outputs-missing' $ghidraHome
    exit 0
}

Write-Status $true $true 'generated' $ghidraHome
Write-Host '      Optional Ghidra map generation complete.' -ForegroundColor Green
exit 0
