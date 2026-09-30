param(
    [string]$GameRoot = "",
    [ValidateRange(1,5)][int]$MaxIterations = 3,
    [ValidateRange(1,16)][int]$MaxEntriesPerIteration = 4,
    [ValidateRange(10,300)][int]$ProbeSeconds = 60,
    [switch]$DisableAutoFfmpeg,
    [switch]$SkipGhidra,
    [switch]$DryRun
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if(!$GameRoot){
    $parent=Split-Path $RepoRoot -Parent
    if(Test-Path -LiteralPath (Join-Path $parent 'SCUS_971.77')){$GameRoot=$parent}
    elseif(Test-Path -LiteralPath 'D:\Recomp Domination\SCUS_971.77'){$GameRoot='D:\Recomp Domination'}
    else{$GameRoot=$parent}
}
$GameRoot=[IO.Path]::GetFullPath($GameRoot)
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$LocalDir=Join-Path $RepoRoot 'analysis\local'
New-Item -ItemType Directory -Force $LocalDir|Out-Null
$ReportPath=Join-Path $LocalDir ('full_auto_bringup_'+$stamp+'.json')

$scripts=[ordered]@{
    preflight=Join-Path $RepoRoot 'scripts\check_environment.ps1'
    prepare=Join-Path $RepoRoot 'scripts\prepare_game_data.ps1'
    inventory=Join-Path $RepoRoot 'scripts\analyze_game_data.ps1'
    ghidra=Join-Path $RepoRoot 'scripts\generate_ghidra_map.ps1'
    bringup=Join-Path $RepoRoot 'scripts\auto_bringup.ps1'
    diagnostics=Join-Path $RepoRoot 'scripts\collect_diagnostics.ps1'
    status=Join-Path $RepoRoot 'scripts\status_downhill.ps1'
}

$stepResults=@()
$started=Get-Date

function Save-Report([string]$StopReason,[int]$ExitCode){
    $result=[pscustomobject][ordered]@{
        generated=(Get-Date -Format o)
        started=$started.ToString('o')
        ended=(Get-Date).ToString('o')
        game_root=$GameRoot
        dry_run=[bool]$DryRun
        max_iterations=$MaxIterations
        max_entries_per_iteration=$MaxEntriesPerIteration
        probe_seconds=$ProbeSeconds
        auto_ffmpeg=(-not $DisableAutoFfmpeg)
        skip_ghidra=[bool]$SkipGhidra
        stop_reason=$StopReason
        exit_code=$ExitCode
        steps=@($script:stepResults)
    }
    [IO.File]::WriteAllText($ReportPath,($result|ConvertTo-Json -Depth 7),(New-Object Text.UTF8Encoding($false)))
    Write-Host ('Full-auto report: '+$ReportPath) -ForegroundColor DarkGray
}

function Invoke-PipelineStep {
    param(
        [string]$Name,
        [string]$Script,
        [string[]]$Arguments=@(),
        [bool]$Fatal=$true
    )

    if(!(Test-Path -LiteralPath $Script)){
        $script:stepResults += [pscustomobject][ordered]@{name=$Name;script=$Script;exit_code=9009;fatal=$Fatal;status='missing'}
        return 9009
    }

    Write-Host ''
    Write-Host ('>>> '+$Name) -ForegroundColor Cyan
    $invokeArgs=@('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$Script)+$Arguments
    & powershell.exe @invokeArgs | ForEach-Object { Write-Host $_ }
    $rc=$LASTEXITCODE
    $script:stepResults += [pscustomobject][ordered]@{
        name=$Name
        script=$Script
        exit_code=$rc
        fatal=$Fatal
        status=$(if($rc-eq 0){'ok'}else{'failed'})
    }
    return [int]$rc
}

$plan=@(
    [pscustomobject]@{name='environment-preflight';required=$true},
    [pscustomobject]@{name='prepare-game-data';required=$true},
    [pscustomobject]@{name='inventory-game-data';required=$false},
    [pscustomobject]@{name='optional-ghidra';required=$false;enabled=(-not $SkipGhidra)},
    [pscustomobject]@{name='guarded-auto-bringup';required=$true},
    [pscustomobject]@{name='collect-diagnostics';required=$false},
    [pscustomobject]@{name='status';required=$false}
)

if($DryRun){
    $script:stepResults=@($plan|ForEach-Object{[pscustomobject][ordered]@{name=$_.name;required=$_.required;enabled=$(if($_.PSObject.Properties['enabled']){$_.enabled}else{$true})}})
    Save-Report 'dry-run' 0
    Write-Host 'FULL AUTO BRING-UP dry-run plan validated.' -ForegroundColor Green
    exit 0
}

$requiredScripts=@($scripts.preflight,$scripts.prepare,$scripts.inventory,$scripts.bringup,$scripts.diagnostics,$scripts.status)
if(!$SkipGhidra){$requiredScripts+=$scripts.ghidra}
foreach($path in $requiredScripts){
    if(!(Test-Path -LiteralPath $path)){
        Write-Host ('Missing required pipeline script: '+$path) -ForegroundColor Red
        $script:stepResults += [pscustomobject][ordered]@{name='script-presence';script=$path;exit_code=9009;fatal=$true;status='missing'}
        Save-Report 'script-missing' 9009
        exit 9009
    }
}

Write-Host '============================================================'
Write-Host ' Recomp Domination - FULL AUTO BRING-UP'
Write-Host '============================================================'
Write-Host ('Game root: '+$GameRoot)
Write-Host ('Iterations: '+$MaxIterations)
Write-Host ('Probe: '+$ProbeSeconds+' s')
Write-Host ('Auto FFmpeg: '+(-not $DisableAutoFfmpeg))
Write-Host ('Ghidra optional: '+(-not $SkipGhidra))

$rc=Invoke-PipelineStep 'environment-preflight' $scripts.preflight @('-GameRoot',$GameRoot) $true
if($rc-ne 0){Save-Report 'preflight-failed' $rc;exit $rc}

$rc=Invoke-PipelineStep 'prepare-game-data' $scripts.prepare @('-GameRoot',$GameRoot) $true
if($rc-ne 0){Save-Report 'game-data-failed' $rc;exit $rc}

$inventoryRc=Invoke-PipelineStep 'inventory-game-data' $scripts.inventory @('-GameRoot',$GameRoot) $false
if($inventoryRc-ne 0){Write-Warning ('Game-data inventory failed with '+$inventoryRc+'; continuing.')} 

if(!$SkipGhidra){
    $csv=Join-Path $RepoRoot 'analysis\SCUS_971.77.functions.csv'
    $toml=Join-Path $RepoRoot 'analysis\SCUS_971.77.ghidra.toml'
    if((Test-Path -LiteralPath $csv)-and(Test-Path -LiteralPath $toml)){
        Write-Host 'Reusing existing Ghidra function map.' -ForegroundColor Green
        $script:stepResults += [pscustomobject][ordered]@{name='optional-ghidra';script=$scripts.ghidra;exit_code=0;fatal=$false;status='reused'}
    } else {
        $ghidraRc=Invoke-PipelineStep 'optional-ghidra' $scripts.ghidra @('-GameRoot',$GameRoot,'-Optional') $false
        if($ghidraRc-ne 0){Write-Warning ('Optional Ghidra pass failed with '+$ghidraRc+'; analyzer fallback will be used.')} 
    }
} else {
    $script:stepResults += [pscustomobject][ordered]@{name='optional-ghidra';script=$scripts.ghidra;exit_code=0;fatal=$false;status='skipped'}
}

$bringupArgs=@('-GameRoot',$GameRoot,'-MaxIterations',[string]$MaxIterations,'-MaxEntriesPerIteration',[string]$MaxEntriesPerIteration,'-ProbeSeconds',[string]$ProbeSeconds)
if($DisableAutoFfmpeg){$bringupArgs+='-DisableAutoFfmpeg'}
$bringupRc=Invoke-PipelineStep 'guarded-auto-bringup' $scripts.bringup $bringupArgs $true

$diagRc=Invoke-PipelineStep 'collect-diagnostics' $scripts.diagnostics @('-GameRoot',$GameRoot) $false
$statusRc=Invoke-PipelineStep 'status' $scripts.status @('-GameRoot',$GameRoot) $false

$finalRc=if($bringupRc-ne 0){$bringupRc}elseif($diagRc-ne 0){$diagRc}else{0}
$stop=if($bringupRc-ne 0){'bringup-failed'}elseif($diagRc-ne 0){'diagnostics-failed'}else{'completed'}
Save-Report $stop $finalRc

Write-Host ''
Write-Host ('FULL AUTO BRING-UP finished: '+$stop+' (exit '+$finalRc+')') -ForegroundColor Cyan
Write-Host ('Downhill output: '+(Join-Path $GameRoot 'DownhillRecompiled'))
exit $finalRc
