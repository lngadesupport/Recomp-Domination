param([string]$Root = "")

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if(!$Root){$Root=Join-Path $RepoRoot '_ci\iteration_compare'}
$Root=[IO.Path]::GetFullPath($Root)
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $Root
$i1=Join-Path $Root 'iteration_01'
$i2=Join-Path $Root 'iteration_02'
New-Item -ItemType Directory -Force $i1,$i2|Out-Null

function Write-Json([string]$Path,$Object){
    [IO.File]::WriteAllText($Path,($Object|ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))
}

Write-Json (Join-Path $i1 'snapshot_manifest.json') ([pscustomobject][ordered]@{reason='rebuild-required';build_mode='single-file';ffmpeg_enabled=$false})
Write-Json (Join-Path $i2 'snapshot_manifest.json') ([pscustomobject][ordered]@{reason='enable-ffmpeg';build_mode='multi-file';ffmpeg_enabled=$true})

Write-Json (Join-Path $i1 'first_boot_probe_triage.json') ([pscustomobject][ordered]@{
    primary_classification='missing-function';furthest_milestone='main';graphics_stage='none';
    runtime_counters=[pscustomobject][ordered]@{max_vif=1;max_gif=2;max_gs_writes=3;max_dma=4}
})
Write-Json (Join-Path $i2 'first_boot_probe_triage.json') ([pscustomobject][ordered]@{
    primary_classification='mpeg-no-ffmpeg';furthest_milestone='guest-graphics';graphics_stage='display-configured';
    runtime_counters=[pscustomobject][ordered]@{max_vif=11;max_gif=7;max_gs_writes=13;max_dma=10}
})

[IO.File]::WriteAllLines((Join-Path $i1 'extra_entry_points.txt'),@('0x00123450'),(New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllLines((Join-Path $i2 'extra_entry_points.txt'),@('0x00123450','0x00123460'),(New-Object Text.UTF8Encoding($false)))
Write-Json (Join-Path $i2 'entry_selection.json') ([pscustomobject][ordered]@{selected=@('0x00123460')})

$Compare=Join-Path $RepoRoot 'scripts\compare_bringup_iterations.ps1'
$Out=Join-Path $Root 'comparison.json'
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $Compare -SessionDir $Root -Out $Out
if($LASTEXITCODE-ne 0){throw "Comparison failed with $LASTEXITCODE"}
if(!(Test-Path -LiteralPath $Out)){throw 'Comparison report missing'}
$r=Get-Content -Raw -LiteralPath $Out|ConvertFrom-Json

if([string]$r.from.name-ne'iteration_01' -or [string]$r.to.name-ne'iteration_02'){throw 'Default iteration selection mismatch'}
if(-not [bool]$r.changes.classification_changed){throw 'Classification change was not detected'}
if(-not [bool]$r.changes.milestone_changed){throw 'Milestone change was not detected'}
if(-not [bool]$r.changes.graphics_stage_changed){throw 'Graphics-stage change was not detected'}
if(-not [bool]$r.changes.build_mode_changed){throw 'Build-mode change was not detected'}
if(-not [bool]$r.changes.ffmpeg_changed){throw 'FFmpeg change was not detected'}
if([int64]$r.changes.vif_delta-ne 10 -or [int64]$r.changes.gif_delta-ne 5 -or [int64]$r.changes.gs_writes_delta-ne 10 -or [int64]$r.changes.dma_delta-ne 6){throw 'Runtime-counter deltas mismatch'}
if(@($r.changes.added_entry_points).Count-ne 1 -or [string]@($r.changes.added_entry_points)[0]-ne'0x00123460'){throw 'Added entry-point diff mismatch'}
if(@($r.changes.removed_entry_points).Count-ne 0){throw 'Unexpected removed entry points'}

# Explicit numeric selection should produce the same pair.
$Out2=Join-Path $Root 'comparison_explicit.json'
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $Compare -SessionDir $Root -FromIteration 1 -ToIteration 2 -Out $Out2
if($LASTEXITCODE-ne 0){throw "Explicit comparison failed with $LASTEXITCODE"}

Write-Host '[iteration-compare-smoke] PASS' -ForegroundColor Green
exit 0
