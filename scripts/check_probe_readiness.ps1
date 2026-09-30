param(
    [Parameter(Mandatory=$true)][string]$Elf,
    [string]$Report = "",
    [string]$Runner = "",
    [string]$Config = "",
    [string]$ExpectedSha256 = "ADFDA7B73A8F05FB20A3F0F318772E9D3797FD4D6C0A6C0078AE392DF0F0CF0C",
    [int64]$ExpectedSize = 1691684,
    [uint32]$ExpectedEntry = 0x0010A008
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$Here=Split-Path -Parent $MyInvocation.MyCommand.Path
$Elf=(Resolve-Path -LiteralPath $Elf).Path
if(!$Report){$Report=Join-Path $Here 'build_report.json'}
if(!$Runner){$Runner=Join-Path $Here 'ps2EntryRunner.exe'}
if(!$Config){$Config=Join-Path $Here 'downhill.auto.toml'}
$Out=Join-Path $Here 'probe_readiness.json'

$critical=@()
$warnings=@()
function Add-Critical([string]$Name,[bool]$Ok,[string]$Detail){
    $script:critical += [pscustomobject][ordered]@{name=$Name;ok=$Ok;detail=$Detail}
}
function Add-Warning([string]$Name,[bool]$Ok,[string]$Detail){
    $script:warnings += [pscustomobject][ordered]@{name=$Name;ok=$Ok;detail=$Detail}
}
function Hex32([uint32]$v){'0x{0:X8}' -f $v}
function Get-Crc32([byte[]]$Data){
    [uint32]$poly=[Convert]::ToUInt32('EDB88320',16)
    [uint32]$crc=[Convert]::ToUInt32('FFFFFFFF',16)
    [uint32[]]$table=New-Object 'UInt32[]' 256
    for($i=0;$i-lt 256;$i++){
        [uint32]$v=$i
        for($j=0;$j-lt 8;$j++){if(($v-band 1)-ne 0){$v=[uint32](($v-shr 1)-bxor$poly)}else{$v=[uint32]($v-shr 1)}}
        $table[$i]=$v
    }
    foreach($byte in $Data){$idx=[int](($crc-bxor[uint32]$byte)-band 0xFF);$crc=[uint32]($table[$idx]-bxor($crc-shr 8))}
    [uint32]($crc-bxor[Convert]::ToUInt32('FFFFFFFF',16))
}

[byte[]]$bytes=[IO.File]::ReadAllBytes($Elf)
$sha=(Get-FileHash -LiteralPath $Elf -Algorithm SHA256).Hash.ToUpperInvariant()
$magic=($bytes.Length-ge 4 -and $bytes[0]-eq 0x7F -and $bytes[1]-eq 0x45 -and $bytes[2]-eq 0x4C -and $bytes[3]-eq 0x46)
$classOk=($bytes.Length-ge 6 -and $bytes[4]-eq 1 -and $bytes[5]-eq 1)
$type=if($bytes.Length-ge 18){[BitConverter]::ToUInt16($bytes,16)}else{0}
$machine=if($bytes.Length-ge 20){[BitConverter]::ToUInt16($bytes,18)}else{0}
[uint32]$entry=if($bytes.Length-ge 28){[BitConverter]::ToUInt32($bytes,24)}else{0}
[uint32]$crc32=Get-Crc32 $bytes

Add-Critical 'ELF magic' $magic $(if($magic){'ELF32 container detected'}else{'invalid ELF magic'})
Add-Critical 'ELF class/endian' $classOk $(if($classOk){'ELF32 little-endian'}else{'expected ELF32 little-endian'})
Add-Critical 'ELF type' ($type-eq 2) ('type='+$type)
Add-Critical 'ELF machine' ($machine-eq 8) ('machine='+$machine)
Add-Critical 'ELF size' ($bytes.Length-eq $ExpectedSize) ('actual='+$bytes.Length+' expected='+$ExpectedSize)
Add-Critical 'ELF SHA-256' ($sha-eq $ExpectedSha256.ToUpperInvariant()) $sha
Add-Critical 'ELF entry' ($entry-eq $ExpectedEntry) ((Hex32 $entry)+' expected='+(Hex32 $ExpectedEntry))

$build=$null
if(Test-Path -LiteralPath $Report){
    try{$build=Get-Content -Raw -LiteralPath $Report|ConvertFrom-Json}catch{Add-Critical 'Build report parse' $false $_.Exception.Message}
}else{Add-Critical 'Build report' $false ('missing: '+$Report)}

if($build){
    Add-Critical 'Build complete' ($build.result-eq 'build-complete') ('result='+$build.result)
    Add-Critical 'Pinned PS2Recomp' ($build.ps2recomp_commit-eq '75d729ce40d7eed9649fd4bb05628dee520f3d0c') ([string]$build.ps2recomp_commit)
    if($build.elf_identity){
        Add-Critical 'Report ELF SHA' (([string]$build.elf_identity.sha256).ToUpperInvariant()-eq$sha) ([string]$build.elf_identity.sha256)
        Add-Critical 'Report ELF size' ([int64]$build.elf_identity.size_bytes-eq$bytes.Length) ([string]$build.elf_identity.size_bytes)
        Add-Critical 'Report ELF entry' ([string]$build.elf_identity.entry-eq(Hex32 $entry)) ([string]$build.elf_identity.entry)
        Add-Critical 'Report ELF CRC32' ([string]$build.elf_identity.crc32_ieee-eq(Hex32 $crc32)) ([string]$build.elf_identity.crc32_ieee)
        Add-Critical 'Report anchors' ([bool]$build.elf_identity.anchors_valid) ('anchors_valid='+$build.elf_identity.anchors_valid)
    }else{Add-Critical 'Report ELF identity' $false 'elf_identity missing from build report'}
    if($build.metrics){
        Add-Critical 'Override CRC32' ([string]$build.metrics.runtime_override_crc32_ieee-eq(Hex32 $crc32)) ([string]$build.metrics.runtime_override_crc32_ieee)
    }else{Add-Critical 'Build metrics' $false 'metrics missing from build report'}
}

if(Test-Path -LiteralPath $Runner){
    $runnerSha=(Get-FileHash -LiteralPath $Runner -Algorithm SHA256).Hash.ToUpperInvariant()
    $expectedRunnerSha=if($build -and $build.metrics){[string]$build.metrics.runner_sha256}else{''}
    Add-Critical 'Runner hash' ($expectedRunnerSha -and $runnerSha-eq$expectedRunnerSha.ToUpperInvariant()) $runnerSha
}else{Add-Critical 'Runner' $false ('missing: '+$Runner)}

if(Test-Path -LiteralPath $Config){
    $cfg=Get-Content -Raw -LiteralPath $Config
    foreach($pc in @('0x0010A008','0x001FB6C0','0x00254050','0x0025C440')){
        Add-Critical ('Config PC '+$pc) ($cfg -match [regex]::Escape($pc)) $(if($cfg -match [regex]::Escape($pc)){'present'}else{'missing'})
    }
    Add-Critical 'Config scePadRead binding' ($cfg -match 'scePadRead@0x00254050') $(if($cfg -match 'scePadRead@0x00254050'){'present'}else{'missing'})
    Add-Critical 'Config sceSifSendCmd binding' ($cfg -match 'sceSifSendCmd@0x0025C440') $(if($cfg -match 'sceSifSendCmd@0x0025C440'){'present'}else{'missing'})
}else{Add-Critical 'Staged config' $false ('missing: '+$Config)}

$gameRoot=Split-Path $Here -Parent
$rootSidecar=Join-Path $gameRoot 'downhill_cd_root.txt'
$imageSidecar=Join-Path $gameRoot 'downhill_cd_image.txt'
$hasRoot=$false;$hasImage=$false
if(Test-Path -LiteralPath $rootSidecar){$v=(Get-Content -LiteralPath $rootSidecar -TotalCount 1).Trim();$hasRoot=($v-and(Test-Path -LiteralPath $v -PathType Container))}
if(Test-Path -LiteralPath $imageSidecar){$v=(Get-Content -LiteralPath $imageSidecar -TotalCount 1).Trim();$hasImage=($v-and(Test-Path -LiteralPath $v -PathType Leaf))}
Add-Warning 'Game data' ($hasRoot-or$hasImage) $(if($hasRoot){'extracted CD root configured'}elseif($hasImage){'ISO configured'}else{'no valid CD root/ISO sidecar; ELF-only boot may stop on file access'})

$failed=@($critical|Where-Object{-not $_.ok})
$report=[ordered]@{
    generated=(Get-Date -Format o)
    ready=($failed.Count-eq 0)
    elf=$Elf
    elf_sha256=$sha
    elf_crc32_ieee=Hex32 $crc32
    runner=[IO.Path]::GetFullPath($Runner)
    build_report=[IO.Path]::GetFullPath($Report)
    critical=$critical
    warnings=$warnings
}
[IO.File]::WriteAllText($Out,($report|ConvertTo-Json -Depth 7),(New-Object Text.UTF8Encoding($false)))

Write-Host '============================================================'
Write-Host ' Recomp Domination - probe readiness'
Write-Host '============================================================'
foreach($row in $critical){$mark=if($row.ok){'[OK]'}else{'[FAIL]'};$color=if($row.ok){'Green'}else{'Red'};Write-Host ($mark+' '+$row.name+' - '+$row.detail) -ForegroundColor $color}
foreach($row in $warnings){$mark=if($row.ok){'[OK]'}else{'[WARN]'};$color=if($row.ok){'Green'}else{'Yellow'};Write-Host ($mark+' '+$row.name+' - '+$row.detail) -ForegroundColor $color}
Write-Host ('Report: '+$Out)
if($failed.Count){exit 1}
Write-Host 'Probe readiness: PASS' -ForegroundColor Green
exit 0
