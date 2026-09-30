param(
    [string]$Root = ""
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if(!$Root){$Root=Join-Path $RepoRoot '_ci\ready'}
$Root=[IO.Path]::GetFullPath($Root)
$Dist=Join-Path $Root 'DownhillRecompiled'
$ElfPath=Join-Path $Root 'SCUS_971.77'
$Runner=Join-Path $Dist 'ps2EntryRunner.exe'
$BuildReport=Join-Path $Dist 'build_report.json'
$Config=Join-Path $Dist 'downhill.auto.toml'
$ReadinessScript=Join-Path $RepoRoot 'scripts\check_probe_readiness.ps1'
$ReadyOut=Join-Path $Dist 'probe_readiness.json'

if(!(Test-Path -LiteralPath $ReadinessScript)){throw "Missing readiness script: $ReadinessScript"}
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $Root
New-Item -ItemType Directory -Force $Dist | Out-Null

function Get-Crc32 {
    param([byte[]]$Data)
    [uint32]$poly=[Convert]::ToUInt32('EDB88320',16)
    [uint32]$crc=[Convert]::ToUInt32('FFFFFFFF',16)
    [uint32[]]$table=New-Object 'UInt32[]' 256
    for($i=0;$i-lt 256;$i++){
        [uint32]$v=$i
        for($j=0;$j-lt 8;$j++){
            if(($v-band 1)-ne 0){$v=[uint32](($v-shr 1)-bxor$poly)}else{$v=[uint32]($v-shr 1)}
        }
        $table[$i]=$v
    }
    foreach($byte in $Data){
        $idx=[int](($crc-bxor[uint32]$byte)-band 0xFF)
        $crc=[uint32]($table[$idx]-bxor($crc-shr 8))
    }
    [uint32]($crc-bxor[Convert]::ToUInt32('FFFFFFFF',16))
}

# Minimal ELF32 little-endian MIPS identity fixture. It is intentionally not
# executable code; readiness validates provenance/identity, not runtime semantics.
[byte[]]$elf=New-Object byte[] 128
$elf[0]=0x7F;$elf[1]=0x45;$elf[2]=0x4C;$elf[3]=0x46;$elf[4]=1;$elf[5]=1
[BitConverter]::GetBytes([uint16]2).CopyTo($elf,16)
[BitConverter]::GetBytes([uint16]8).CopyTo($elf,18)
[BitConverter]::GetBytes([uint32]0x0010A008).CopyTo($elf,24)
[IO.File]::WriteAllBytes($ElfPath,$elf)

# Deterministic runner fixture. The readiness gate binds its hash to build_report.json.
[byte[]]$runnerBytes=1..96
[IO.File]::WriteAllBytes($Runner,$runnerBytes)

$sha=(Get-FileHash -LiteralPath $ElfPath -Algorithm SHA256).Hash.ToUpperInvariant()
$runnerSha=(Get-FileHash -LiteralPath $Runner -Algorithm SHA256).Hash.ToUpperInvariant()
[uint32]$crc=Get-Crc32 $elf
$crcText=('0x{0:X8}' -f $crc)

$build=[ordered]@{
    result='build-complete'
    ps2recomp_commit='75d729ce40d7eed9649fd4bb05628dee520f3d0c'
    elf_identity=[ordered]@{
        size_bytes=128
        sha256=$sha
        entry='0x0010A008'
        pcsx2_elf_crc='0x00000000'
        crc32_ieee=$crcText
        anchors_valid=$true
    }
    metrics=[ordered]@{
        runner_sha256=$runnerSha
        runtime_override_crc32_ieee=$crcText
    }
}
[IO.File]::WriteAllText($BuildReport,($build|ConvertTo-Json -Depth 6),(New-Object Text.UTF8Encoding($false)))

$cfg=@'
[general]
entry_points = [
  "0x0010A008",
  "0x001FB6C0",
  "0x00254050",
  "0x0025C440",
]
stubs = [
  "scePadRead@0x00254050",
  "sceSifSendCmd@0x0025C440",
]
'@
[IO.File]::WriteAllText($Config,$cfg,(New-Object Text.UTF8Encoding($false)))

Write-Host '[readiness-smoke] accepting matched ELF/runner/report...' -ForegroundColor Cyan
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $ReadinessScript `
    -Elf $ElfPath -Report $BuildReport -Runner $Runner -Config $Config -Out $ReadyOut `
    -ExpectedSha256 $sha -ExpectedSize 128
$rc=$LASTEXITCODE
if($rc-ne 0){throw "Matching readiness fixture failed with exit code $rc"}

if(!(Test-Path -LiteralPath $ReadyOut)){throw "Readiness JSON was not created: $ReadyOut"}
$ready=Get-Content -Raw -LiteralPath $ReadyOut|ConvertFrom-Json
if(!$ready.ready){throw 'Matching readiness fixture was not marked ready'}

Write-Host '[readiness-smoke] rejecting stale modified runner...' -ForegroundColor Cyan
[IO.File]::AppendAllText($Runner,'stale',[Text.Encoding]::ASCII)
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $ReadinessScript `
    -Elf $ElfPath -Report $BuildReport -Runner $Runner -Config $Config -Out $ReadyOut `
    -ExpectedSha256 $sha -ExpectedSize 128
$rc=$LASTEXITCODE
if($rc-ne 1){throw "Expected stale runner rejection exit 1, got $rc"}
$ready=Get-Content -Raw -LiteralPath $ReadyOut|ConvertFrom-Json
if($ready.ready){throw 'Stale runner was incorrectly accepted'}

Write-Host '[readiness-smoke] PASS' -ForegroundColor Green
$global:LASTEXITCODE=0
exit 0
