param(
    [Parameter(Mandatory=$true)][string]$SessionDir,
    [int]$FromIteration = 0,
    [int]$ToIteration = 0,
    [string]$Out = ""
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$SessionDir=(Resolve-Path -LiteralPath $SessionDir).Path

function Get-IterationDirectories {
    @(Get-ChildItem -LiteralPath $SessionDir -Directory -Filter 'iteration_*' -ErrorAction Stop |
        Where-Object {$_.Name -match '^iteration_(\d+)$'} |
        Sort-Object Name)
}

$dirs=Get-IterationDirectories
if($dirs.Count-lt 2){throw 'At least two iteration_XX directories are required for comparison.'}

function Resolve-IterationDir([int]$Number,[bool]$UseLast){
    if($Number-gt 0){
        $name=('iteration_{0:D2}' -f $Number)
        $hit=@($dirs|Where-Object{$_.Name-eq$name})|Select-Object -First 1
        if(!$hit){throw "Iteration not found: $name"}
        return $hit.FullName
    }
    if($UseLast){return $dirs[-1].FullName}
    return $dirs[-2].FullName
}

$FromDir=Resolve-IterationDir $FromIteration $false
$ToDir=Resolve-IterationDir $ToIteration $true
if($FromDir-eq$ToDir){throw 'From and To iterations must be different.'}

function Read-JsonOptional([string]$Path){
    if(!(Test-Path -LiteralPath $Path -PathType Leaf)){return $null}
    try{return ([IO.File]::ReadAllText($Path)|ConvertFrom-Json)}catch{return $null}
}

function Read-LinesOptional([string]$Path){
    if(!(Test-Path -LiteralPath $Path -PathType Leaf)){return @()}
    @((Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)|ForEach-Object{$_.Trim()}|Where-Object{$_})
}

function Get-IterationState([string]$Dir){
    $manifest=Read-JsonOptional (Join-Path $Dir 'snapshot_manifest.json')
    $triage=Read-JsonOptional (Join-Path $Dir 'first_boot_probe_triage.json')
    if(!$triage){$triage=Read-JsonOptional (Join-Path $Dir 'first_boot_triage.json')}
    $selection=Read-JsonOptional (Join-Path $Dir 'entry_selection.json')
    $build=Read-JsonOptional (Join-Path $Dir 'build_report.json')
    $extra=Read-LinesOptional (Join-Path $Dir 'extra_entry_points.txt')

    $runtime=$null
    if($triage-and$triage.PSObject.Properties['runtime_counters']){$runtime=$triage.runtime_counters}

    [pscustomobject][ordered]@{
        name=(Split-Path $Dir -Leaf)
        path=$Dir
        reason=if($manifest-and$manifest.PSObject.Properties['reason']){[string]$manifest.reason}else{''}
        build_mode=if($manifest-and$manifest.PSObject.Properties['build_mode']){[string]$manifest.build_mode}else{''}
        ffmpeg_enabled=if($manifest-and$manifest.PSObject.Properties['ffmpeg_enabled']){[bool]$manifest.ffmpeg_enabled}else{$false}
        classification=if($triage-and$triage.PSObject.Properties['primary_classification']){[string]$triage.primary_classification}else{''}
        milestone=if($triage-and$triage.PSObject.Properties['furthest_milestone']){[string]$triage.furthest_milestone}else{''}
        graphics_stage=if($triage-and$triage.PSObject.Properties['graphics_stage']){[string]$triage.graphics_stage}else{''}
        max_vif=if($runtime-and$runtime.PSObject.Properties['max_vif']){[int64]$runtime.max_vif}else{0}
        max_gif=if($runtime-and$runtime.PSObject.Properties['max_gif']){[int64]$runtime.max_gif}else{0}
        max_gs_writes=if($runtime-and$runtime.PSObject.Properties['max_gs_writes']){[int64]$runtime.max_gs_writes}else{0}
        max_dma=if($runtime-and$runtime.PSObject.Properties['max_dma']){[int64]$runtime.max_dma}else{0}
        selected_entries=if($selection-and$selection.PSObject.Properties['selected']){@($selection.selected|ForEach-Object{[string]$_})}else{@()}
        extra_entries=@($extra)
        runner_sha256=if($build-and$build.PSObject.Properties['metrics']-and$build.metrics.PSObject.Properties['runner_sha256']){[string]$build.metrics.runner_sha256}else{''}
    }
}

$from=Get-IterationState $FromDir
$to=Get-IterationState $ToDir

$addedEntries=@($to.extra_entries|Where-Object{$_ -notin $from.extra_entries})
$removedEntries=@($from.extra_entries|Where-Object{$_ -notin $to.extra_entries})

$changes=[pscustomobject][ordered]@{
    classification_changed=($from.classification-ne$to.classification)
    milestone_changed=($from.milestone-ne$to.milestone)
    graphics_stage_changed=($from.graphics_stage-ne$to.graphics_stage)
    build_mode_changed=($from.build_mode-ne$to.build_mode)
    ffmpeg_changed=($from.ffmpeg_enabled-ne$to.ffmpeg_enabled)
    vif_delta=[int64]($to.max_vif-$from.max_vif)
    gif_delta=[int64]($to.max_gif-$from.max_gif)
    gs_writes_delta=[int64]($to.max_gs_writes-$from.max_gs_writes)
    dma_delta=[int64]($to.max_dma-$from.max_dma)
    added_entry_points=$addedEntries
    removed_entry_points=$removedEntries
}

$result=[pscustomobject][ordered]@{
    generated=(Get-Date -Format o)
    session_dir=$SessionDir
    from=$from
    to=$to
    changes=$changes
}

if(!$Out){$Out=Join-Path $SessionDir ('compare_'+$from.name+'_to_'+$to.name+'.json')}
$Out=[IO.Path]::GetFullPath($Out)
[IO.File]::WriteAllText($Out,($result|ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))

Write-Host '============================================================'
Write-Host ' Recomp Domination - bring-up iteration comparison'
Write-Host '============================================================'
Write-Host ('From: '+$from.name+'  reason='+$from.reason+'  class='+$from.classification+'  milestone='+$from.milestone+'  graphics='+$from.graphics_stage)
Write-Host ('To:   '+$to.name+'  reason='+$to.reason+'  class='+$to.classification+'  milestone='+$to.milestone+'  graphics='+$to.graphics_stage)
Write-Host ('Mode: '+$from.build_mode+' -> '+$to.build_mode+'; FFmpeg: '+$from.ffmpeg_enabled+' -> '+$to.ffmpeg_enabled)
Write-Host ('Counters delta: VIF={0} GIF={1} GS={2} DMA={3}' -f $changes.vif_delta,$changes.gif_delta,$changes.gs_writes_delta,$changes.dma_delta)
if($addedEntries.Count){Write-Host ('Added entry points: '+($addedEntries -join ', ')) -ForegroundColor Yellow}
if($removedEntries.Count){Write-Host ('Removed entry points: '+($removedEntries -join ', ')) -ForegroundColor Yellow}
Write-Host ('Report: '+$Out)
exit 0
