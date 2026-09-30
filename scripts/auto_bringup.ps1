param(
    [string]$GameRoot = "",
    [ValidateRange(1,5)][int]$MaxIterations = 3,
    [ValidateRange(1,16)][int]$MaxEntriesPerIteration = 4,
    [ValidateRange(10,300)][int]$ProbeSeconds = 60,
    [switch]$DisableAutoFfmpeg
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if(!$GameRoot){
    $parent=Split-Path $RepoRoot -Parent
    if(Test-Path -LiteralPath (Join-Path $parent 'SCUS_971.77')){$GameRoot=$parent}
    elseif(Test-Path -LiteralPath 'D:\Recomp Domination\SCUS_971.77'){$GameRoot='D:\Recomp Domination'}
    else{throw 'SCUS_971.77 not found. Pass -GameRoot.'}
}
$GameRoot=[IO.Path]::GetFullPath($GameRoot)
$Elf=Join-Path $GameRoot 'SCUS_971.77'
$Dist=Join-Path $GameRoot 'DownhillRecompiled'
$Extra=Join-Path $RepoRoot 'config\downhill.extra_entry_points.local.txt'
$Build=Join-Path $RepoRoot 'scripts\build_downhill.ps1'
$Selector=Join-Path $RepoRoot 'scripts\select_bringup_entry_points.ps1'
$Planner=Join-Path $RepoRoot 'scripts\plan_bringup_action.ps1'
$Snapshot=Join-Path $RepoRoot 'scripts\snapshot_bringup_iteration.ps1'
$Diag=Join-Path $RepoRoot 'scripts\collect_diagnostics.ps1'
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$Out=Join-Path $RepoRoot ('analysis\local\auto_bringup_'+$stamp+'.json')
$SessionDir=Join-Path $RepoRoot ('analysis\local\bringup_sessions\'+$stamp)
New-Item -ItemType Directory -Force -Path (Split-Path $Out -Parent),$SessionDir|Out-Null

foreach($required in @($Build,$Selector,$Planner,$Snapshot)){
    if(!(Test-Path -LiteralPath $required)){throw "Required bring-up script missing: $required"}
}

$backup=$null
if(Test-Path -LiteralPath $Extra){
    $backup=$Extra+'.before_auto_'+$stamp
    Copy-Item -Force -LiteralPath $Extra -Destination $backup
}

$iterations=@()
$stopReason='max-iterations'
$finalExitCode=0
$useMulti=$false
$useFfmpeg=$false
$autoFfmpegEnabled=(-not $DisableAutoFfmpeg)

function Save-IterationSnapshot {
    param(
        [int]$Iteration,
        [string]$Reason,
        [string]$Selection = ''
    )

    $snapshotArgs=@(
        '-NoLogo','-NoProfile','-ExecutionPolicy','Bypass',
        '-File',$Snapshot,
        '-GameRoot',$GameRoot,
        '-SessionDir',$SessionDir,
        '-Iteration',[string]$Iteration,
        '-Reason',$Reason,
        '-BuildMode',$(if($useMulti){'multi-file'}else{'single-file'})
    )
    if($useFfmpeg){$snapshotArgs+='-FfmpegEnabled'}
    if($Selection){$snapshotArgs+=@('-Selection',$Selection)}
    if(Test-Path -LiteralPath $Extra){$snapshotArgs+=@('-ExtraEntryPoints',$Extra)}

    & powershell.exe @snapshotArgs
    if($LASTEXITCODE -ne 0){
        Write-Warning ("Iteration snapshot failed with exit code {0}" -f $LASTEXITCODE)
    }

    return (Join-Path $SessionDir ('iteration_{0:D2}' -f $Iteration))
}

for($i=1;$i-le$MaxIterations;$i++){
    Write-Host ''
    Write-Host ('=== AUTO BRING-UP ITERATION {0}/{1} ===' -f $i,$MaxIterations) -ForegroundColor Cyan
    Write-Host ('Mode: {0}; FFmpeg: {1}' -f $(if($useMulti){'multi-file'}else{'single-file'}),$useFfmpeg) -ForegroundColor DarkGray

    $buildArgs=@('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$Build,'-GameRoot',$GameRoot)
    if($useMulti){$buildArgs+='-MultiFileOutput'}
    if($useFfmpeg){$buildArgs+='-EnableFfmpeg'}
    & powershell.exe @buildArgs
    $buildRc=$LASTEXITCODE

    if($buildRc -ne 0 -and !$useMulti){
        Write-Warning ('Single-file build failed with code '+$buildRc+'; retrying multi-file.')
        $useMulti=$true
        $buildArgs=@('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$Build,'-GameRoot',$GameRoot,'-MultiFileOutput')
        if($useFfmpeg){$buildArgs+='-EnableFfmpeg'}
        & powershell.exe @buildArgs
        $buildRc=$LASTEXITCODE
    }

    if($buildRc -ne 0){
        $stopReason='build-failed'
        $finalExitCode=10
        $snapshotDir=Save-IterationSnapshot -Iteration $i -Reason $stopReason
        $iterations+=[pscustomobject]@{
            iteration=$i;build_rc=$buildRc;probe_rc=$null;accepted=@();reason=$stopReason
            build_mode=$(if($useMulti){'multi-file'}else{'single-file'});ffmpeg_enabled=$useFfmpeg;snapshot=$snapshotDir
        }
        break
    }

    $probeScript=Join-Path $Dist 'run_downhill_probe.ps1'
    if(!(Test-Path -LiteralPath $probeScript)){
        $stopReason='probe-script-missing'
        $finalExitCode=11
        $snapshotDir=Save-IterationSnapshot -Iteration $i -Reason $stopReason
        $iterations+=[pscustomobject]@{
            iteration=$i;build_rc=$buildRc;probe_rc=$null;accepted=@();reason=$stopReason
            build_mode=$(if($useMulti){'multi-file'}else{'single-file'});ffmpeg_enabled=$useFfmpeg;snapshot=$snapshotDir
        }
        break
    }

    $readinessScript=Join-Path $Dist 'check_probe_readiness.ps1'
    if(!(Test-Path -LiteralPath $readinessScript)){
        $stopReason='readiness-script-missing'
        $finalExitCode=14
        $snapshotDir=Save-IterationSnapshot -Iteration $i -Reason $stopReason
        $iterations+=[pscustomobject]@{
            iteration=$i;build_rc=$buildRc;probe_rc=$null;accepted=@();reason=$stopReason
            build_mode=$(if($useMulti){'multi-file'}else{'single-file'});ffmpeg_enabled=$useFfmpeg;snapshot=$snapshotDir
        }
        break
    }

    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $readinessScript -Elf $Elf
    $readyRc=$LASTEXITCODE
    if($readyRc -ne 0){
        $stopReason='readiness-failed'
        $finalExitCode=14
        $snapshotDir=Save-IterationSnapshot -Iteration $i -Reason $stopReason
        $iterations+=[pscustomobject]@{
            iteration=$i;build_rc=$buildRc;probe_rc=$null;accepted=@();reason=$stopReason;readiness_rc=$readyRc
            build_mode=$(if($useMulti){'multi-file'}else{'single-file'});ffmpeg_enabled=$useFfmpeg;snapshot=$snapshotDir
        }
        break
    }

    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $probeScript -Elf $Elf -TimeoutSeconds $ProbeSeconds
    $probeRc=$LASTEXITCODE

    $suggestions=Join-Path $Dist 'first_boot_probe_suggestions.json'
    $triage=Join-Path $Dist 'first_boot_probe_triage.json'

    if(!(Test-Path -LiteralPath $triage)){
        $stopReason='triage-missing'
        $finalExitCode=12
        $snapshotDir=Save-IterationSnapshot -Iteration $i -Reason $stopReason
        $iterations+=[pscustomobject]@{
            iteration=$i;build_rc=$buildRc;probe_rc=$probeRc;accepted=@();reason=$stopReason
            build_mode=$(if($useMulti){'multi-file'}else{'single-file'});ffmpeg_enabled=$useFfmpeg;snapshot=$snapshotDir
        }
        break
    }

    $actionOut=Join-Path $RepoRoot ('analysis\local\auto_bringup_action_'+$stamp+'_'+$i+'.json')
    $plannerArgs=@('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$Planner,'-Triage',$triage,'-Out',$actionOut)
    if($useFfmpeg){$plannerArgs+='-FfmpegEnabled'}
    & powershell.exe @plannerArgs
    $planRc=$LASTEXITCODE
    $plan=Get-Content -Raw -LiteralPath $actionOut|ConvertFrom-Json

    if([string]$plan.action -eq 'enable-ffmpeg' -and $autoFfmpegEnabled -and !$useFfmpeg){
        $snapshotDir=Save-IterationSnapshot -Iteration $i -Reason 'enable-ffmpeg'
        $iterations+=[pscustomobject]@{
            iteration=$i;build_rc=$buildRc;probe_rc=$probeRc;accepted=@();reason='enable-ffmpeg'
            classification=$plan.primary_classification;build_mode=$(if($useMulti){'multi-file'}else{'single-file'})
            ffmpeg_enabled=$useFfmpeg;snapshot=$snapshotDir
        }

        if($i -ge $MaxIterations){
            $stopReason='ffmpeg-escalation-max-iterations'
            $finalExitCode=15
            break
        }

        Write-Host 'MPEG blocker detected without FFmpeg; enabling FFmpeg for the next bounded iteration.' -ForegroundColor Yellow
        $useFfmpeg=$true
        $stopReason='ffmpeg-escalation'
        continue
    }

    if([string]$plan.action -eq 'enable-ffmpeg' -and !$autoFfmpegEnabled){
        $stopReason='ffmpeg-escalation-disabled'
        $snapshotDir=Save-IterationSnapshot -Iteration $i -Reason $stopReason
        $iterations+=[pscustomobject]@{
            iteration=$i;build_rc=$buildRc;probe_rc=$probeRc;accepted=@();reason=$stopReason
            classification=$plan.primary_classification;build_mode=$(if($useMulti){'multi-file'}else{'single-file'})
            ffmpeg_enabled=$useFfmpeg;snapshot=$snapshotDir
        }
        break
    }

    if([string]$plan.action -eq 'stop' -or $planRc -eq 3){
        $stopReason='triage-blocker'
        $snapshotDir=Save-IterationSnapshot -Iteration $i -Reason $stopReason
        $iterations+=[pscustomobject]@{
            iteration=$i;build_rc=$buildRc;probe_rc=$probeRc;accepted=@();reason=$stopReason
            classification=$plan.primary_classification;action_reason=$plan.reason
            build_mode=$(if($useMulti){'multi-file'}else{'single-file'});ffmpeg_enabled=$useFfmpeg;snapshot=$snapshotDir
        }
        break
    }

    if($planRc -ne 0 -or [string]$plan.action -ne 'entry-points'){
        $stopReason='planner-failed'
        $finalExitCode=15
        $snapshotDir=Save-IterationSnapshot -Iteration $i -Reason $stopReason
        $iterations+=[pscustomobject]@{
            iteration=$i;build_rc=$buildRc;probe_rc=$probeRc;accepted=@();reason=$stopReason
            classification=$plan.primary_classification;action=$plan.action
            build_mode=$(if($useMulti){'multi-file'}else{'single-file'});ffmpeg_enabled=$useFfmpeg;snapshot=$snapshotDir
        }
        break
    }

    if(!(Test-Path -LiteralPath $suggestions)){
        $stopReason='suggestions-missing'
        $finalExitCode=12
        $snapshotDir=Save-IterationSnapshot -Iteration $i -Reason $stopReason
        $iterations+=[pscustomobject]@{
            iteration=$i;build_rc=$buildRc;probe_rc=$probeRc;accepted=@();reason=$stopReason
            classification=$plan.primary_classification;build_mode=$(if($useMulti){'multi-file'}else{'single-file'})
            ffmpeg_enabled=$useFfmpeg;snapshot=$snapshotDir
        }
        break
    }

    $selection=Join-Path $RepoRoot ('analysis\local\auto_entry_selection_'+$stamp+'_'+$i+'.json')
    $selectorArgs=@(
        '-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$Selector,
        '-Suggestions',$suggestions,'-Triage',$triage,
        '-MaxSelected',$MaxEntriesPerIteration,'-Out',$selection
    )
    if(Test-Path -LiteralPath $Extra){$selectorArgs+=@('-Existing',$Extra)}
    & powershell.exe @selectorArgs
    $selectRc=$LASTEXITCODE
    $sel=Get-Content -Raw -LiteralPath $selection|ConvertFrom-Json

    if($selectRc -eq 3){
        $stopReason='triage-blocker'
        $snapshotDir=Save-IterationSnapshot -Iteration $i -Reason $stopReason -Selection $selection
        $iterations+=[pscustomobject]@{
            iteration=$i;build_rc=$buildRc;probe_rc=$probeRc;accepted=@();reason=$stopReason
            classification=$sel.primary_classification;build_mode=$(if($useMulti){'multi-file'}else{'single-file'})
            ffmpeg_enabled=$useFfmpeg;snapshot=$snapshotDir
        }
        break
    }
    if($selectRc -ne 0){
        $stopReason='selection-failed'
        $finalExitCode=13
        $snapshotDir=Save-IterationSnapshot -Iteration $i -Reason $stopReason -Selection $selection
        $iterations+=[pscustomobject]@{
            iteration=$i;build_rc=$buildRc;probe_rc=$probeRc;accepted=@();reason=$stopReason
            build_mode=$(if($useMulti){'multi-file'}else{'single-file'});ffmpeg_enabled=$useFfmpeg;snapshot=$snapshotDir
        }
        break
    }

    $selected=@($sel.selected)
    if($selected.Count -eq 0){
        $stopReason='no-new-entry-points'
        $snapshotDir=Save-IterationSnapshot -Iteration $i -Reason $stopReason -Selection $selection
        $iterations+=[pscustomobject]@{
            iteration=$i;build_rc=$buildRc;probe_rc=$probeRc;accepted=@();reason=$stopReason
            classification=$sel.primary_classification;build_mode=$(if($useMulti){'multi-file'}else{'single-file'})
            ffmpeg_enabled=$useFfmpeg;snapshot=$snapshotDir
        }
        break
    }

    $current=@()
    if(Test-Path -LiteralPath $Extra){
        $current=@(Get-Content -LiteralPath $Extra|ForEach-Object{$_.Trim()}|Where-Object{$_ -match '^0x[0-9A-Fa-f]{8}$'})
    }
    $merged=@($current+$selected|Sort-Object -Unique)
    [IO.File]::WriteAllLines($Extra,$merged,(New-Object Text.UTF8Encoding($false)))
    Write-Host ('Accepted for next iteration: '+($selected -join ', ')) -ForegroundColor Yellow

    $snapshotDir=Save-IterationSnapshot -Iteration $i -Reason 'rebuild-required' -Selection $selection
    $iterations+=[pscustomobject]@{
        iteration=$i;build_rc=$buildRc;probe_rc=$probeRc;accepted=$selected;reason='rebuild-required'
        classification=$sel.primary_classification;build_mode=$(if($useMulti){'multi-file'}else{'single-file'})
        ffmpeg_enabled=$useFfmpeg;snapshot=$snapshotDir
    }
}

if(Test-Path -LiteralPath $Diag){
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $Diag -GameRoot $GameRoot
}

$report=[pscustomobject][ordered]@{
    generated=(Get-Date -Format o)
    game_root=$GameRoot
    max_iterations=$MaxIterations
    probe_seconds=$ProbeSeconds
    max_entries_per_iteration=$MaxEntriesPerIteration
    auto_ffmpeg_enabled=$autoFfmpegEnabled
    ffmpeg_enabled_final=$useFfmpeg
    used_multi_file=$useMulti
    local_entry_file=$Extra
    backup=$backup
    session_dir=$SessionDir
    stop_reason=$stopReason
    exit_code=$finalExitCode
    iterations=$iterations
}
[IO.File]::WriteAllText($Out,($report|ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))
Write-Host ''
Write-Host ('Auto bring-up finished: '+$stopReason) -ForegroundColor Cyan
Write-Host ('Report: '+$Out)
Write-Host ('Session: '+$SessionDir)
if($backup){Write-Host ('Original local entries backup: '+$backup)}
exit $finalExitCode
