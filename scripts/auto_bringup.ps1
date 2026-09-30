param(
    [string]$GameRoot = "",
    [ValidateRange(1,5)][int]$MaxIterations = 3,
    [ValidateRange(1,16)][int]$MaxEntriesPerIteration = 4,
    [ValidateRange(10,300)][int]$ProbeSeconds = 60
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
$Diag=Join-Path $RepoRoot 'scripts\collect_diagnostics.ps1'
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$Out=Join-Path $RepoRoot ('analysis\local\auto_bringup_'+$stamp+'.json')
New-Item -ItemType Directory -Force -Path (Split-Path $Out -Parent)|Out-Null

$backup=$null
if(Test-Path -LiteralPath $Extra){
    $backup=$Extra+'.before_auto_'+$stamp
    Copy-Item -Force -LiteralPath $Extra -Destination $backup
}

$iterations=@()
$stopReason='max-iterations'
$finalExitCode=0
$useMulti=$false

for($i=1;$i-le$MaxIterations;$i++){
    Write-Host ''
    Write-Host ('=== AUTO BRING-UP ITERATION {0}/{1} ===' -f $i,$MaxIterations) -ForegroundColor Cyan

    $buildArgs=@('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$Build,'-GameRoot',$GameRoot)
    if($useMulti){$buildArgs+='-MultiFileOutput'}
    & powershell.exe @buildArgs
    $buildRc=$LASTEXITCODE

    if($buildRc -ne 0 -and !$useMulti){
        Write-Warning ('Single-file build failed with code '+$buildRc+'; retrying multi-file.')
        $useMulti=$true
        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $Build -GameRoot $GameRoot -MultiFileOutput
        $buildRc=$LASTEXITCODE
    }
    if($buildRc -ne 0){
        $stopReason='build-failed'
        $finalExitCode=10
        $iterations+=[pscustomobject]@{iteration=$i;build_rc=$buildRc;probe_rc=$null;accepted=@();reason=$stopReason}
        break
    }

    $probeScript=Join-Path $Dist 'run_downhill_probe.ps1'
    if(!(Test-Path -LiteralPath $probeScript)){
        $stopReason='probe-script-missing'
        $finalExitCode=11
        $iterations+=[pscustomobject]@{iteration=$i;build_rc=$buildRc;probe_rc=$null;accepted=@();reason=$stopReason}
        break
    }

    $readinessScript=Join-Path $Dist 'check_probe_readiness.ps1'
    if(!(Test-Path -LiteralPath $readinessScript)){
        $stopReason='readiness-script-missing'
        $finalExitCode=14
        $iterations+=[pscustomobject]@{iteration=$i;build_rc=$buildRc;probe_rc=$null;accepted=@();reason=$stopReason}
        break
    }
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $readinessScript -Elf $Elf
    $readyRc=$LASTEXITCODE
    if($readyRc -ne 0){
        $stopReason='readiness-failed'
        $finalExitCode=14
        $iterations+=[pscustomobject]@{iteration=$i;build_rc=$buildRc;probe_rc=$null;accepted=@();reason=$stopReason;readiness_rc=$readyRc}
        break
    }

    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $probeScript -Elf $Elf -TimeoutSeconds $ProbeSeconds
    $probeRc=$LASTEXITCODE

    $suggestions=Join-Path $Dist 'first_boot_probe_suggestions.json'
    $triage=Join-Path $Dist 'first_boot_probe_triage.json'
    if(!(Test-Path -LiteralPath $suggestions)){
        $stopReason='suggestions-missing'
        $finalExitCode=12
        $iterations+=[pscustomobject]@{iteration=$i;build_rc=$buildRc;probe_rc=$probeRc;accepted=@();reason=$stopReason}
        break
    }

    $selection=Join-Path $RepoRoot ('analysis\local\auto_entry_selection_'+$stamp+'_'+$i+'.json')
    $selectorArgs=@('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$Selector,'-Suggestions',$suggestions,'-MaxSelected',$MaxEntriesPerIteration,'-Out',$selection)
    if(Test-Path -LiteralPath $triage){$selectorArgs+=@('-Triage',$triage)}
    if(Test-Path -LiteralPath $Extra){$selectorArgs+=@('-Existing',$Extra)}
    & powershell.exe @selectorArgs
    $selectRc=$LASTEXITCODE
    $sel=Get-Content -Raw -LiteralPath $selection | ConvertFrom-Json

    if($selectRc -eq 3){
        $stopReason='triage-blocker'
        $iterations+=[pscustomobject]@{iteration=$i;build_rc=$buildRc;probe_rc=$probeRc;accepted=@();reason=$stopReason;classification=$sel.primary_classification}
        break
    }
    if($selectRc -ne 0){
        $stopReason='selection-failed'
        $finalExitCode=13
        $iterations+=[pscustomobject]@{iteration=$i;build_rc=$buildRc;probe_rc=$probeRc;accepted=@();reason=$stopReason}
        break
    }

    $selected=@($sel.selected)
    if($selected.Count -eq 0){
        $stopReason='no-new-entry-points'
        $iterations+=[pscustomobject]@{iteration=$i;build_rc=$buildRc;probe_rc=$probeRc;accepted=@();reason=$stopReason;classification=$sel.primary_classification}
        break
    }

    $current=@()
    if(Test-Path -LiteralPath $Extra){$current=@(Get-Content -LiteralPath $Extra|ForEach-Object{$_.Trim()}|Where-Object{$_ -match '^0x[0-9A-Fa-f]{8}$'})}
    $merged=@($current+$selected|Sort-Object -Unique)
    [IO.File]::WriteAllLines($Extra,$merged,(New-Object Text.UTF8Encoding($false)))
    Write-Host ('Accepted for next iteration: '+($selected -join ', ')) -ForegroundColor Yellow

    $iterations+=[pscustomobject]@{iteration=$i;build_rc=$buildRc;probe_rc=$probeRc;accepted=$selected;reason='rebuild-required';classification=$sel.primary_classification}
}

if(Test-Path -LiteralPath $Diag){
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $Diag -GameRoot $GameRoot
}

$report=[ordered]@{
    generated=(Get-Date -Format o)
    game_root=$GameRoot
    max_iterations=$MaxIterations
    probe_seconds=$ProbeSeconds
    max_entries_per_iteration=$MaxEntriesPerIteration
    used_multi_file=$useMulti
    local_entry_file=$Extra
    backup=$backup
    stop_reason=$stopReason
    exit_code=$finalExitCode
    iterations=$iterations
}
[IO.File]::WriteAllText($Out,($report|ConvertTo-Json -Depth 7),(New-Object Text.UTF8Encoding($false)))
Write-Host ''
Write-Host ('Auto bring-up finished: '+$stopReason) -ForegroundColor Cyan
Write-Host ('Report: '+$Out)
if($backup){Write-Host ('Original local entries backup: '+$backup)}
exit $finalExitCode
