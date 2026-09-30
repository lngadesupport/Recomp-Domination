param(
    [string]$GameRoot = "",
    [string]$GhidraHome = "",
    [switch]$Optional
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$PinnedPs2Recomp = '75d729ce40d7eed9649fd4bb05628dee520f3d0c'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ThirdParty = Join-Path $RepoRoot 'third_party'
$Ps2RecompRoot = Join-Path $ThirdParty 'PS2Recomp'
$AnalysisDir = Join-Path $RepoRoot 'analysis'
$LocalDir = Join-Path $AnalysisDir 'local'
New-Item -ItemType Directory -Force -Path $ThirdParty,$AnalysisDir,$LocalDir | Out-Null

if(!$GameRoot){
    $parent=Split-Path $RepoRoot -Parent
    if(Test-Path -LiteralPath (Join-Path $parent 'SCUS_971.77')){$GameRoot=$parent}
    elseif(Test-Path -LiteralPath 'D:\Recomp Domination\SCUS_971.77'){$GameRoot='D:\Recomp Domination'}
    else{throw 'SCUS_971.77 was not found. Pass -GameRoot explicitly.'}
}
$GameRoot=[IO.Path]::GetFullPath($GameRoot)
$Elf=Join-Path $GameRoot 'SCUS_971.77'
if(!(Test-Path -LiteralPath $Elf)){throw "Missing ELF: $Elf"}

function Find-GhidraHeadless {
    param([string]$Requested)
    $homes=New-Object System.Collections.Generic.List[string]
    if($Requested){$homes.Add([IO.Path]::GetFullPath($Requested))}
    if($env:GHIDRA_HOME){$homes.Add($env:GHIDRA_HOME)}
    foreach($parent in @($env:ProgramFiles,$env:USERPROFILE,(Join-Path $env:USERPROFILE 'Downloads'),'C:\')){
        if(!$parent -or !(Test-Path -LiteralPath $parent)){continue}
        Get-ChildItem -LiteralPath $parent -Directory -Filter 'ghidra*' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            ForEach-Object {$homes.Add($_.FullName)}
    }
    foreach($home in $homes){
        $candidate=Join-Path $home 'support\analyzeHeadless.bat'
        if(Test-Path -LiteralPath $candidate){
            return [pscustomobject]@{home=[IO.Path]::GetFullPath($home);exe=[IO.Path]::GetFullPath($candidate)}
        }
    }
    return $null
}

$git=(Get-Command git -ErrorAction SilentlyContinue)
if(!$git){throw 'Git is required to obtain the pinned PS2Recomp Ghidra exporter.'}

if(!(Test-Path -LiteralPath (Join-Path $Ps2RecompRoot '.git'))){
    & $git.Source clone https://github.com/ran-j/PS2Recomp.git $Ps2RecompRoot
    if($LASTEXITCODE -ne 0){throw 'Failed to clone PS2Recomp.'}
}

$havePinnedCommit = $false
& $git.Source -C $Ps2RecompRoot cat-file -e ($PinnedPs2Recomp + '^{commit}') 2>$null
if($LASTEXITCODE -eq 0){$havePinnedCommit=$true}

if(!$havePinnedCommit){
    & $git.Source -C $Ps2RecompRoot fetch origin $PinnedPs2Recomp --depth=1
    if($LASTEXITCODE -ne 0){throw 'Pinned PS2Recomp commit is not local and could not be fetched.'}
}

& $git.Source -C $Ps2RecompRoot reset --hard $PinnedPs2Recomp
if($LASTEXITCODE -ne 0){throw 'Failed to reset PS2Recomp to pinned commit.'}

$ghidra=Find-GhidraHeadless $GhidraHome
if(!$ghidra){
    if($Optional){
        Write-Host 'Ghidra was not found; continuing with ps2_analyzer fallback.' -ForegroundColor Yellow
        exit 0
    }
    throw 'Ghidra was not found. Install Ghidra, set GHIDRA_HOME, or pass -GhidraHome.'
}

$scriptDir=Join-Path $Ps2RecompRoot 'ps2xRecomp\tools\ghidra'
$script=Join-Path $scriptDir 'ExportPS2Functions.java'
if(!(Test-Path -LiteralPath $script)){throw "Missing exporter: $script"}

$patchExporter = Join-Path $RepoRoot 'scripts\patch_ghidra_exporter.ps1'
if (!(Test-Path -LiteralPath $patchExporter)) { throw "Missing headless exporter patch helper: $patchExporter" }
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $patchExporter -ExporterPath $script
if ($LASTEXITCODE -ne 0) { throw 'Headless Ghidra exporter adaptation failed.' }
$toml=Join-Path $AnalysisDir 'SCUS_971.77.ghidra.toml'
$csv=Join-Path $AnalysisDir 'SCUS_971.77.functions.csv'
$projectDir=Join-Path $LocalDir 'ghidra_project'
$projectName='Downhill_SCUS_97177_' + (Get-Date -Format 'yyyyMMdd_HHmmss')
$log=Join-Path $LocalDir 'ghidra_headless.log'
$scriptLog=Join-Path $LocalDir 'ghidra_script.log'
New-Item -ItemType Directory -Force -Path $projectDir | Out-Null
Remove-Item -Force -ErrorAction SilentlyContinue $toml,$csv,$log,$scriptLog

Write-Host '============================================================'
Write-Host ' Recomp Domination - Ghidra headless function map'
Write-Host '============================================================'
Write-Host ("Ghidra: " + $ghidra.home)
Write-Host ("ELF:    " + $Elf)
Write-Host ("CSV:    " + $csv)
Write-Host ''

$args=@(
    $projectDir,
    $projectName,
    '-import',$Elf,
    '-analysisTimeoutPerFile','1200',
    '-deleteProject',
    '-scriptPath',$scriptDir,
    '-postScript','ExportPS2Functions.java',$toml,$csv,
    '-log',$log,
    '-scriptlog',$scriptLog
)
& $ghidra.exe @args
if($LASTEXITCODE -ne 0){throw "Ghidra headless failed with exit code $LASTEXITCODE. See $log and $scriptLog"}

if(!(Test-Path -LiteralPath $csv)){throw 'Ghidra completed but did not produce the function CSV.'}
if(!(Test-Path -LiteralPath $toml)){throw 'Ghidra completed but did not produce the TOML.'}

$csvLines=@(Get-Content -LiteralPath $csv)
if($csvLines.Count -lt 2){throw 'Ghidra CSV contains no function records.'}
$header=$csvLines[0].Trim()
if($header -notmatch '(?i)^Name,Start,End,Size$'){throw "Unexpected Ghidra CSV header: $header"}

$records=[Math]::Max(0,$csvLines.Count-1)
$known=@('0x0010A008','0x001FB6C0','0x00254050','0x0025C440')
$presence=[ordered]@{}
$csvText=$csvLines -join [Environment]::NewLine
foreach($addr in $known){$presence[$addr]=[regex]::IsMatch($csvText,'(?i),'+[regex]::Escape($addr)+',')}

$report=[ordered]@{
    generated_at=(Get-Date -Format o)
    ghidra_home=$ghidra.home
    elf=$Elf
    function_csv=$csv
    export_toml=$toml
    csv_records=$records
    known_address_presence=$presence
    ps2recomp_commit=$PinnedPs2Recomp
    ghidra_log=$log
    script_log=$scriptLog
}
[IO.File]::WriteAllText((Join-Path $LocalDir 'ghidra_map_report.json'),($report|ConvertTo-Json -Depth 6),(New-Object Text.UTF8Encoding($false)))

Write-Host ''
Write-Host ("Ghidra map complete: $records records") -ForegroundColor Green
Write-Host ("CSV: $csv") -ForegroundColor Green
Write-Host 'BUILD_DOWNHILL.cmd will detect this CSV automatically on the next build.'
