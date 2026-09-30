param([string]$Root = "")

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if(!$Root){$Root=Join-Path $RepoRoot '_ci\triage'}
$Root=[IO.Path]::GetFullPath($Root)
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $Root
New-Item -ItemType Directory -Force $Root | Out-Null

$Triage=Join-Path $RepoRoot 'scripts\triage_first_boot.ps1'
if(!(Test-Path -LiteralPath $Triage)){throw "Missing triage script: $Triage"}

function Read-Json([string]$Path){
    if(!(Test-Path -LiteralPath $Path)){throw "Expected JSON missing: $Path"}
    return ([IO.File]::ReadAllText($Path)|ConvertFrom-Json)
}

# Case 1: missing EE function after meaningful graphics activity.
$log1=Join-Path $Root 'missing_function.log'
$out1=Join-Path $Root 'missing_function.json'
$lines1=@(
    'ELF file loaded successfully. Entry point: 0x0010A008',
    'Function main enter pc=0x001FB6C0',
    '[run:tick] tick=120 pc=0x00123450 ra=0x00111110 sp=0x01FFF000 gp=0x00200000 dispfb1=0x00000001 display1=0x00000002 activeThreads=2 dma=3 gif=4 gsw=5 vif=6',
    'missing function lookupFunction pc=0x00123450 ra=0x00111110'
)
[IO.File]::WriteAllLines($log1,$lines1,(New-Object Text.UTF8Encoding($false)))
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $Triage -Log $log1 -Out $out1
if($LASTEXITCODE-ne 0){throw "triage case1 failed with $LASTEXITCODE"}
$r1=Read-Json $out1
if([string]$r1.primary_classification-ne 'missing-function'){throw "case1 primary=$($r1.primary_classification)"}
if([string]$r1.graphics_stage-ne 'display-configured'){throw "case1 graphics=$($r1.graphics_stage)"}
if([string]$r1.furthest_milestone-ne 'guest-graphics'){throw "case1 milestone=$($r1.furthest_milestone)"}
if([int]$r1.runtime_counters.max_vif-ne 6 -or [int]$r1.runtime_counters.max_gif-ne 4 -or [int]$r1.runtime_counters.max_gs_writes-ne 5){throw 'case1 runtime counters mismatch'}

# Case 2: repeated guest file-open failures retain path/PC information.
$log2=Join-Path $Root 'fileio.log'
$out2=Join-Path $Root 'fileio.json'
$lines2=@(
    "[FileIO:open-failed] guest='cdrom0:\\DATA\\RACE.BIN;1' flags=0x1 pc=0x00123450",
    "[FileIO:open-failed] guest='cdrom0:\\DATA\\RACE.BIN;1' flags=0x1 pc=0x00123450",
    "[FileIO:open-failed] guest='cdrom0:\\DATA\\RACE.BIN;1' flags=0x1 pc=0x00123450"
)
[IO.File]::WriteAllLines($log2,$lines2,(New-Object Text.UTF8Encoding($false)))
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $Triage -Log $log2 -Out $out2
if($LASTEXITCODE-ne 0){throw "triage case2 failed with $LASTEXITCODE"}
$r2=Read-Json $out2
if([int]$r2.file_io.total_failures-ne 3){throw "case2 failures=$($r2.file_io.total_failures)"}
if(@($r2.file_io.repeated_paths).Count-ne 1){throw 'case2 repeated-path detection failed'}
$first=@($r2.file_io.open_failures)[0]
if([string]$first.first_pc-ne '0X00123450'){throw "case2 pc=$($first.first_pc)"}

# Case 3: MPEG without FFmpeg and repeated picture waits is recognized as its own blocker.
$log3=Join-Path $Root 'mpeg.log'
$out3=Join-Path $Root 'mpeg.json'
$lines3=@(
    '[MPEG] runtime built without FFmpeg',
    '[MPEG:GetPicture] waiting for decoded picture',
    '[MPEG:GetPicture] waiting for decoded picture'
)
[IO.File]::WriteAllLines($log3,$lines3,(New-Object Text.UTF8Encoding($false)))
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $Triage -Log $log3 -Out $out3
if($LASTEXITCODE-ne 0){throw "triage case3 failed with $LASTEXITCODE"}
$r3=Read-Json $out3
if([string]$r3.primary_classification-ne 'mpeg-no-ffmpeg'){throw "case3 primary=$($r3.primary_classification)"}
if(-not [bool]$r3.mpeg.no_ffmpeg -or [int]$r3.mpeg.picture_waits-ne 2){throw 'case3 MPEG counters mismatch'}

Write-Host '[triage-smoke] PASS' -ForegroundColor Green
exit 0
