param([string]$Root = "")

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if(!$Root){$Root=Join-Path $RepoRoot '_ci\full_auto'}
$Root=[IO.Path]::GetFullPath($Root)
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $Root
New-Item -ItemType Directory -Force $Root|Out-Null

$Script=Join-Path $RepoRoot 'scripts\full_auto_bringup.ps1'
if(!(Test-Path -LiteralPath $Script)){throw "Missing full-auto script: $Script"}

function Load-Report([string]$Path){
    if(!(Test-Path -LiteralPath $Path)){throw "Expected report missing: $Path"}
    return ([IO.File]::ReadAllText($Path)|ConvertFrom-Json)
}

function Assert-StepPlan($Report,[bool]$GhidraEnabled){
    $expected=@(
        'environment-preflight',
        'prepare-game-data',
        'inventory-game-data',
        'optional-ghidra',
        'guarded-auto-bringup',
        'collect-diagnostics',
        'status'
    )
    $names=@($Report.steps|ForEach-Object{[string]$_.name})
    foreach($name in $expected){
        if($names -notcontains $name){throw "Dry-run plan missing step: $name"}
    }
    if($names.Count-ne$expected.Count){throw "Unexpected dry-run step count: $($names.Count)"}
    $ghidra=@($Report.steps|Where-Object{$_.name-eq'optional-ghidra'})[0]
    if([bool]$ghidra.enabled-ne$GhidraEnabled){throw "Ghidra enabled mismatch: expected=$GhidraEnabled actual=$($ghidra.enabled)"}
}

$fakeGame=Join-Path $Root 'game with spaces'
$out1=Join-Path $Root 'default.json'
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $Script `
    -GameRoot $fakeGame -MaxIterations 3 -MaxEntriesPerIteration 4 -ProbeSeconds 60 `
    -DryRun -Out $out1
$rc=$LASTEXITCODE
if($rc-ne 0){throw "Default dry-run failed with $rc"}
$r1=Load-Report $out1
if(-not [bool]$r1.dry_run){throw 'Default report did not mark dry_run=true'}
if([string]$r1.stop_reason-ne'dry-run' -or [int]$r1.exit_code-ne 0){throw 'Default dry-run result mismatch'}
if(-not [bool]$r1.auto_ffmpeg){throw 'Auto FFmpeg should default to enabled'}
if([bool]$r1.skip_ghidra){throw 'Ghidra should default to optional/enabled'}
if([int]$r1.max_iterations-ne 3 -or [int]$r1.max_entries_per_iteration-ne 4 -or [int]$r1.probe_seconds-ne 60){throw 'Default limits mismatch'}
Assert-StepPlan $r1 $true

$out2=Join-Path $Root 'disabled.json'
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $Script `
    -GameRoot $fakeGame -MaxIterations 2 -MaxEntriesPerIteration 2 -ProbeSeconds 30 `
    -DisableAutoFfmpeg -SkipGhidra -DryRun -Out $out2
$rc=$LASTEXITCODE
if($rc-ne 0){throw "Disabled-feature dry-run failed with $rc"}
$r2=Load-Report $out2
if([bool]$r2.auto_ffmpeg){throw 'DisableAutoFfmpeg was not reflected in report'}
if(-not [bool]$r2.skip_ghidra){throw 'SkipGhidra was not reflected in report'}
if([int]$r2.max_iterations-ne 2 -or [int]$r2.max_entries_per_iteration-ne 2 -or [int]$r2.probe_seconds-ne 30){throw 'Custom limits mismatch'}
Assert-StepPlan $r2 $false

# Dry-run must not require or synthesize proprietary game files.
if(Test-Path -LiteralPath (Join-Path $fakeGame 'SCUS_971.77')){throw 'Dry-run unexpectedly created a retail ELF fixture'}

Write-Host '[full-auto-smoke] PASS' -ForegroundColor Green
exit 0
