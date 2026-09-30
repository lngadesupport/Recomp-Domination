param(
    [Parameter(Mandatory=$true)][string]$GameRoot,
    [Parameter(Mandatory=$true)][string]$SessionDir,
    [Parameter(Mandatory=$true)][ValidateRange(1,99)][int]$Iteration,
    [string]$Reason = 'snapshot',
    [string]$BuildMode = 'single-file',
    [switch]$FfmpegEnabled,
    [string]$Selection = '',
    [string]$ExtraEntryPoints = ''
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$GameRoot=[IO.Path]::GetFullPath($GameRoot)
$SessionDir=[IO.Path]::GetFullPath($SessionDir)
$Dist=Join-Path $GameRoot 'DownhillRecompiled'
$IterationDir=Join-Path $SessionDir ('iteration_{0:D2}' -f $Iteration)
New-Item -ItemType Directory -Force $IterationDir | Out-Null

$script:copied=@()
function Copy-IfPresent([string]$Source,[string]$Name){
    if(!$Source -or !(Test-Path -LiteralPath $Source -PathType Leaf)){return}
    $dest=Join-Path $IterationDir $Name
    Copy-Item -Force -LiteralPath $Source -Destination $dest
    $script:copied += [pscustomobject][ordered]@{
        name=$Name
        bytes=[int64](Get-Item -LiteralPath $dest).Length
        sha256=(Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash
    }
}

# Never copy the retail ELF, ISO, extracted game assets, RAR volumes or generated
# C++ here. This snapshot is diagnostics/configuration only.
$distFiles=@(
    'build_report.json',
    'probe_readiness.json',
    'first_boot_probe.json',
    'first_boot_probe_latest.log',
    'first_boot_probe_triage.json',
    'first_boot_probe_suggestions.json',
    'first_boot_probe_function_trace_latest.log',
    'first_boot_latest.log',
    'first_boot_triage.json',
    'first_boot_suggestions.json',
    'recompiled_report.json',
    'stub_audit.json',
    'stub_filter_report.json',
    'SCUS_971.77.deep.json',
    'downhill.auto.toml'
)
foreach($name in $distFiles){Copy-IfPresent (Join-Path $Dist $name) $name}

Copy-IfPresent (Join-Path $RepoRoot 'config\downhill.auto.toml') 'repo_downhill.auto.toml'
Copy-IfPresent (Join-Path $RepoRoot 'analysis\local\SCUS_971.77.deep.json') 'repo_SCUS_971.77.deep.json'
if($Selection){Copy-IfPresent $Selection 'entry_selection.json'}
if($ExtraEntryPoints){Copy-IfPresent $ExtraEntryPoints 'extra_entry_points.txt'}

$latestBuildLog=Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'logs') -Filter 'build_downhill_*.log' -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if($latestBuildLog){Copy-IfPresent $latestBuildLog.FullName 'build_latest.log'}

$manifest=[pscustomobject][ordered]@{
    generated=(Get-Date -Format o)
    iteration=$Iteration
    reason=$Reason
    build_mode=$BuildMode
    ffmpeg_enabled=[bool]$FfmpegEnabled
    game_root=$GameRoot
    session_dir=$SessionDir
    iteration_dir=$IterationDir
    files=@($script:copied)
}
$manifestPath=Join-Path $IterationDir 'snapshot_manifest.json'
[IO.File]::WriteAllText($manifestPath,($manifest|ConvertTo-Json -Depth 6),(New-Object Text.UTF8Encoding($false)))

Write-Host ('Bring-up snapshot: iteration={0} reason={1} files={2}' -f $Iteration,$Reason,@($script:copied).Count) -ForegroundColor DarkGray
Write-Host ('  '+$IterationDir) -ForegroundColor DarkGray
