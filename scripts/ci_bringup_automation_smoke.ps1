param([string]$Root = "")

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if(!$Root){$Root=Join-Path $RepoRoot '_ci\bringup_automation'}
$Root=[IO.Path]::GetFullPath($Root)
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $Root
New-Item -ItemType Directory -Force $Root | Out-Null

$Planner=Join-Path $RepoRoot 'scripts\plan_bringup_action.ps1'
$Snapshot=Join-Path $RepoRoot 'scripts\snapshot_bringup_iteration.ps1'
foreach($p in @($Planner,$Snapshot)){if(!(Test-Path -LiteralPath $p)){throw "Missing script: $p"}}

function Write-Triage([string]$Name,[string]$Primary){
    $path=Join-Path $Root ($Name+'.json')
    $obj=[pscustomobject][ordered]@{primary_classification=$Primary}
    [IO.File]::WriteAllText($path,($obj|ConvertTo-Json -Depth 3),(New-Object Text.UTF8Encoding($false)))
    return $path
}

function Run-Plan([string]$Name,[string]$Primary,[bool]$Ffmpeg,[string]$ExpectedAction,[int]$ExpectedRc){
    $triage=Write-Triage $Name $Primary
    $out=Join-Path $Root ($Name+'_action.json')
    $args=@('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$Planner,'-Triage',$triage,'-Out',$out)
    if($Ffmpeg){$args+='-FfmpegEnabled'}
    & powershell.exe @args | ForEach-Object { Write-Host $_ }
    $rc=$LASTEXITCODE
    if($rc-ne$ExpectedRc){throw "$Name expected rc=$ExpectedRc got $rc"}
    $plan=Get-Content -Raw -LiteralPath $out|ConvertFrom-Json
    if([string]$plan.action-ne$ExpectedAction){throw "$Name expected action=$ExpectedAction got $($plan.action)"}
    return $plan
}

$p1=Run-Plan 'missing' 'missing-function' $false 'entry-points' 0
$p2=Run-Plan 'mpeg_off' 'mpeg-no-ffmpeg' $false 'enable-ffmpeg' 0
$p3=Run-Plan 'mpeg_on' 'mpeg-no-ffmpeg' $true 'stop' 3
$p4=Run-Plan 'vif' 'vif-vu-gs' $false 'stop' 3
$p5=Run-Plan 'fileio' 'file-io' $false 'stop' 3

if(-not [bool]$p1.automatic -or -not [bool]$p2.automatic){throw 'Eligible actions must be automatic'}
if([bool]$p3.automatic -or [bool]$p4.automatic -or [bool]$p5.automatic){throw 'Blocked actions must not be automatic'}

# Snapshot smoke: diagnostics/config are copied; proprietary-like payloads are not.
$GameRoot=Join-Path $Root 'game'
$Dist=Join-Path $GameRoot 'DownhillRecompiled'
$Session=Join-Path $Root 'session'
New-Item -ItemType Directory -Force $Dist | Out-Null
[IO.File]::WriteAllText((Join-Path $Dist 'build_report.json'),'{"result":"build-complete"}',(New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText((Join-Path $Dist 'first_boot_probe_triage.json'),'{"primary_classification":"missing-function"}',(New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText((Join-Path $Dist 'downhill.auto.toml'),'[general]',(New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllBytes((Join-Path $GameRoot 'SCUS_971.77'),[byte[]](1..64))
[IO.File]::WriteAllBytes((Join-Path $GameRoot 'game.iso'),[byte[]](1..64))

$snapArgs=@(
    '-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$Snapshot,
    '-GameRoot',$GameRoot,'-SessionDir',$Session,'-Iteration','1','-Reason','smoke',
    '-BuildMode','multi-file','-FfmpegEnabled'
)
& powershell.exe @snapArgs
if($LASTEXITCODE-ne 0){throw "Snapshot smoke failed with $LASTEXITCODE"}

$iter=Join-Path $Session 'iteration_01'
$manifest=Join-Path $iter 'snapshot_manifest.json'
if(!(Test-Path -LiteralPath $manifest)){throw 'Snapshot manifest missing'}
$m=Get-Content -Raw -LiteralPath $manifest|ConvertFrom-Json
if([string]$m.reason-ne'smoke' -or [string]$m.build_mode-ne'multi-file' -or -not [bool]$m.ffmpeg_enabled){throw 'Snapshot manifest metadata mismatch'}
if(!(Test-Path -LiteralPath (Join-Path $iter 'build_report.json'))){throw 'Snapshot did not copy build report'}
if(!(Test-Path -LiteralPath (Join-Path $iter 'first_boot_probe_triage.json'))){throw 'Snapshot did not copy triage'}
if(Test-Path -LiteralPath (Join-Path $iter 'SCUS_971.77')){throw 'Snapshot leaked proprietary ELF'}
if(Test-Path -LiteralPath (Join-Path $iter 'game.iso')){throw 'Snapshot leaked ISO'}

Write-Host '[bringup-automation-smoke] PASS' -ForegroundColor Green
exit 0
