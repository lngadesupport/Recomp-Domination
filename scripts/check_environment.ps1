param([string]$GameRoot = "")

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (!$GameRoot) {
    $parent = Split-Path $RepoRoot -Parent
    if (Test-Path -LiteralPath (Join-Path $parent 'SCUS_971.77')) { $GameRoot = $parent }
    elseif (Test-Path -LiteralPath 'D:\Recomp Domination\SCUS_971.77') { $GameRoot = 'D:\Recomp Domination' }
    else { $GameRoot = $parent }
}
$GameRoot = [IO.Path]::GetFullPath($GameRoot)
$Elf = Join-Path $GameRoot 'SCUS_971.77'

$checks = New-Object System.Collections.Generic.List[object]
function Add-Check([string]$Name,[bool]$Ok,[string]$Detail) {
    $checks.Add([pscustomobject]@{ name=$Name; ok=$Ok; detail=$Detail })
    $mark = if($Ok){'[OK]'}else{'[FAIL]'}
    $color = if($Ok){'Green'}else{'Red'}
    Write-Host ($mark + ' ' + $Name + ' - ' + $Detail) -ForegroundColor $color
}

Write-Host '============================================================'
Write-Host ' Recomp Domination - environment preflight'
Write-Host '============================================================'
Write-Host ('Repo: ' + $RepoRoot)
Write-Host ('Game: ' + $GameRoot)
Write-Host ''

$git = Get-Command git -ErrorAction SilentlyContinue
Add-Check 'Git' ([bool]$git) $(if($git){((& git --version) -join ' ')}else{'not found'})

$cmake = Get-Command cmake -ErrorAction SilentlyContinue
$cmakeDetail = 'not found'
if($cmake){
    $cmakeDetail = ((& cmake --version | Select-Object -First 1) -join '')
}
Add-Check 'CMake' ([bool]$cmake) $cmakeDetail

$psVersion = $PSVersionTable.PSVersion.ToString()
Add-Check 'Windows PowerShell' ($PSVersionTable.PSEdition -eq 'Desktop' -or $PSVersionTable.Platform -eq 'Win32NT' -or $env:OS -eq 'Windows_NT') ('version ' + $psVersion)

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vsOk = Test-Path -LiteralPath $vswhere
$vsInstall = ''
if($vsOk){
    $vsInstall = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1)
    $vsOk = [bool]$vsInstall
}
Add-Check 'MSVC x64 workload' $vsOk $(if($vsOk){$vsInstall}else{'Desktop development with C++ not found'})

$elfOk = Test-Path -LiteralPath $Elf
$elfDetail = if($elfOk){((Get-Item -LiteralPath $Elf).Length.ToString() + ' bytes')}else{'missing: ' + $Elf}
if($elfOk -and (Get-Item -LiteralPath $Elf).Length -ne 1691684){$elfOk=$false;$elfDetail='unexpected size: '+(Get-Item -LiteralPath $Elf).Length}
Add-Check 'SCUS_971.77' $elfOk $elfDetail

if($elfOk){
    $sha=(Get-FileHash -LiteralPath $Elf -Algorithm SHA256).Hash.ToUpperInvariant()
    $expected='ADFDA7B73A8F05FB20A3F0F318772E9D3797FD4D6C0A6C0078AE392DF0F0CF0C'
    Add-Check 'ELF SHA-256' ($sha -eq $expected) $sha
}

$driveRoot = [IO.Path]::GetPathRoot($GameRoot)
try {
    $drive = New-Object IO.DriveInfo($driveRoot)
    [double]$freeGiB = $drive.AvailableFreeSpace / 1GB
    Add-Check 'Free disk space' ($freeGiB -ge 15) (('{0:N1} GiB free on {1}' -f $freeGiB,$driveRoot))
} catch {
    Add-Check 'Free disk space' $false $_.Exception.Message
}

$internetOk=$false
try{
    $tcp=New-Object Net.Sockets.TcpClient
    $ar=$tcp.BeginConnect('github.com',443,$null,$null)
    $internetOk=$ar.AsyncWaitHandle.WaitOne(3000)
    if($internetOk){$tcp.EndConnect($ar)}
    $tcp.Close()
}catch{}
Add-Check 'GitHub connectivity' $internetOk $(if($internetOk){'github.com:443 reachable'}else{'not reachable; first build needs internet'})

$failed=@($checks | Where-Object { -not $_.ok })
$report=[ordered]@{
    generated=(Get-Date -Format o)
    repo_root=$RepoRoot
    game_root=$GameRoot
    checks=$checks
    success=($failed.Count -eq 0)
}
$out=Join-Path $RepoRoot 'analysis\local\environment.json'
New-Item -ItemType Directory -Force -Path (Split-Path $out -Parent) | Out-Null
[IO.File]::WriteAllText($out,($report|ConvertTo-Json -Depth 5),(New-Object Text.UTF8Encoding($false)))
Write-Host ''
Write-Host ('Report: ' + $out)
if($failed.Count -gt 0){
    Write-Host ('Preflight failed: ' + $failed.Count + ' check(s).') -ForegroundColor Red
    exit 1
}
Write-Host 'Environment is ready for BUILD_DOWNHILL.cmd.' -ForegroundColor Green
exit 0
