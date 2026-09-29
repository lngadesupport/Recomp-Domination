param(
    [string]$GameRoot = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (!$GameRoot) {
    $parent = Split-Path $RepoRoot -Parent
    if (Test-Path -LiteralPath (Join-Path $parent 'SCUS_971.77')) { $GameRoot = $parent }
    elseif (Test-Path -LiteralPath 'D:\Recomp Domination\SCUS_971.77') { $GameRoot = 'D:\Recomp Domination' }
    else { throw 'SCUS_971.77 was not found. Pass -GameRoot explicitly.' }
}
$GameRoot = [IO.Path]::GetFullPath($GameRoot)
if (!(Test-Path -LiteralPath (Join-Path $GameRoot 'SCUS_971.77'))) { throw "SCUS_971.77 not found under $GameRoot" }

$cdRootSidecar = Join-Path $GameRoot 'downhill_cd_root.txt'
$cdImageSidecar = Join-Path $GameRoot 'downhill_cd_image.txt'
$extractRoot = Join-Path $GameRoot 'game_data'
$analysisDir = Join-Path $RepoRoot 'analysis\local'
New-Item -ItemType Directory -Force -Path $analysisDir | Out-Null

function Write-Sidecar([string]$Path,[string]$Value) {
    [IO.File]::WriteAllText($Path,[IO.Path]::GetFullPath($Value),(New-Object Text.UTF8Encoding($false)))
}

function Find-SystemCnf {
    param([string]$Root,[bool]$Recursive=$false)
    $direct = Join-Path $Root 'SYSTEM.CNF'
    if (Test-Path -LiteralPath $direct) { return (Get-Item -LiteralPath $direct).FullName }
    if (!$Recursive) {
        foreach($dir in @(Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue)) {
            $candidate=Join-Path $dir.FullName 'SYSTEM.CNF'
            if(Test-Path -LiteralPath $candidate){return (Get-Item -LiteralPath $candidate).FullName}
        }
        return $null
    }
    $hit = Get-ChildItem -LiteralPath $Root -Filter 'SYSTEM.CNF' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if($hit){return $hit.FullName}
    return $null
}

function Find-Iso {
    param([string]$Root,[bool]$Recursive=$false)
    $items = if($Recursive){
        Get-ChildItem -LiteralPath $Root -File -Recurse -ErrorAction SilentlyContinue
    } else {
        Get-ChildItem -LiteralPath $Root -File -ErrorAction SilentlyContinue
    }
    $hit=$items | Where-Object {$_.Extension -ieq '.iso'} | Sort-Object Length -Descending | Select-Object -First 1
    if($hit){return $hit.FullName}
    return $null
}

function Find-7Zip {
    foreach($name in @('7z.exe','7zz.exe','7z','7zz')){
        $cmd=Get-Command $name -ErrorAction SilentlyContinue
        if($cmd){return $cmd.Source}
    }
    foreach($candidate in @(
        (Join-Path $env:ProgramFiles '7-Zip\7z.exe'),
        (if(${env:ProgramFiles(x86)}){Join-Path ${env:ProgramFiles(x86)} '7-Zip\7z.exe'}else{$null})
    )){if($candidate -and (Test-Path -LiteralPath $candidate)){return $candidate}}
    return $null
}

function New-CanonicalMultipartView {
    param([System.IO.FileInfo]$FirstVolume)

    $m = [regex]::Match($FirstVolume.Name, '^(?<base>.+)\.part(?<digits>0*1)\.rar$systemCnf = Find-SystemCnf $GameRoot $false
$iso = Find-Iso $GameRoot $false

if(!$systemCnf -and (Test-Path -LiteralPath $extractRoot)){ $systemCnf=Find-SystemCnf $extractRoot $true }
if(!$iso -and (Test-Path -LiteralPath $extractRoot)){ $iso=Find-Iso $extractRoot $true }

$archive=$null
$archiveFor7Zip=$null
$multipartStaging=$null
$sevenZip=$null
$extracted=$false

if(!$systemCnf -and !$iso){
    $archive = Get-ChildItem -LiteralPath $GameRoot -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '(?i)\.part0*1\.rar$' } |
        Sort-Object Name | Select-Object -First 1

    if($archive){
        $sevenZip=Find-7Zip
        if(!$sevenZip){
            throw "Multipart RAR found ($($archive.Name)), but 7-Zip was not found. Install 7-Zip or place 7z.exe in PATH."
        }

        $archiveFor7Zip = New-CanonicalMultipartView $archive
        $multipartStaging = Split-Path $archiveFor7Zip -Parent
        Write-Host "Testing multipart archive through canonical hardlinks: $archiveFor7Zip"
        & $sevenZip 't' $archiveFor7Zip
        if($LASTEXITCODE -ne 0){throw "7-Zip archive test failed with exit code $LASTEXITCODE."}

        New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null
        Write-Host "Extracting local game data to: $extractRoot"
        & $sevenZip 'x' '-y' ('-o'+$extractRoot) $archiveFor7Zip
        if($LASTEXITCODE -ne 0){throw "7-Zip extraction failed with exit code $LASTEXITCODE."}
        $extracted=$true

        if($multipartStaging -and (Test-Path -LiteralPath $multipartStaging)){
            Remove-Item -LiteralPath $multipartStaging -Recurse -Force
            $multipartStaging=$null
        }

        $systemCnf=Find-SystemCnf $extractRoot $true
        $iso=Find-Iso $extractRoot $true
    }
}

if($systemCnf){
    $root=Split-Path $systemCnf -Parent
    Write-Sidecar $cdRootSidecar $root
    Write-Host "CD root configured: $root" -ForegroundColor Green
}
if($iso){
    Write-Sidecar $cdImageSidecar $iso
    Write-Host "CD image configured: $iso" -ForegroundColor Green
}

if(!$systemCnf -and !$iso){
    throw 'No SYSTEM.CNF or ISO was found. Keep the original disc image or extracted disc files in the game folder, or place the multipart RAR volumes there and run this command again.'
}

$report=[ordered]@{
    prepared_at=(Get-Date -Format o)
    game_root=$GameRoot
    extracted_archive=if($archive){$archive.FullName}else{$null}
    archive_used_for_7zip=$archiveFor7Zip
    multipart_staging=$multipartStaging
    extraction_performed=$extracted
    seven_zip=$sevenZip
    system_cnf=$systemCnf
    cd_root=if($systemCnf){Split-Path $systemCnf -Parent}else{$null}
    iso=$iso
    cd_root_sidecar=if(Test-Path $cdRootSidecar){$cdRootSidecar}else{$null}
    cd_image_sidecar=if(Test-Path $cdImageSidecar){$cdImageSidecar}else{$null}
}
[IO.File]::WriteAllText((Join-Path $analysisDir 'game_data_prepared.json'),($report|ConvertTo-Json -Depth 5),(New-Object Text.UTF8Encoding($false)))

Write-Host ''
Write-Host 'Game data preparation complete.' -ForegroundColor Green
Write-Host 'No proprietary game data was added to Git.'
, 'IgnoreCase')
    if(!$m.Success){ return $FirstVolume.FullName }

    $base = $m.Groups['base'].Value
    $width = $m.Groups['digits'].Value.Length
    $volumePattern = '^' + [regex]::Escape($base) + '\.part0*(?<part>[0-9]+)(?:\([0-9]+\))?\.rar$systemCnf = Find-SystemCnf $GameRoot $false
$iso = Find-Iso $GameRoot $false

if(!$systemCnf -and (Test-Path -LiteralPath $extractRoot)){ $systemCnf=Find-SystemCnf $extractRoot $true }
if(!$iso -and (Test-Path -LiteralPath $extractRoot)){ $iso=Find-Iso $extractRoot $true }

$archive=$null
$sevenZip=$null
$extracted=$false

if(!$systemCnf -and !$iso){
    $archive = Get-ChildItem -LiteralPath $GameRoot -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '(?i)\.part0*1\.rar$' } |
        Sort-Object Name | Select-Object -First 1

    if($archive){
        $sevenZip=Find-7Zip
        if(!$sevenZip){
            throw "Multipart RAR found ($($archive.Name)), but 7-Zip was not found. Install 7-Zip or place 7z.exe in PATH."
        }

        Write-Host "Testing multipart archive: $($archive.FullName)"
        & $sevenZip 't' $archive.FullName
        if($LASTEXITCODE -ne 0){throw "7-Zip archive test failed with exit code $LASTEXITCODE."}

        New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null
        Write-Host "Extracting local game data to: $extractRoot"
        & $sevenZip 'x' '-y' ('-o'+$extractRoot) $archive.FullName
        if($LASTEXITCODE -ne 0){throw "7-Zip extraction failed with exit code $LASTEXITCODE."}
        $extracted=$true

        $systemCnf=Find-SystemCnf $extractRoot $true
        $iso=Find-Iso $extractRoot $true
    }
}

if($systemCnf){
    $root=Split-Path $systemCnf -Parent
    Write-Sidecar $cdRootSidecar $root
    Write-Host "CD root configured: $root" -ForegroundColor Green
}
if($iso){
    Write-Sidecar $cdImageSidecar $iso
    Write-Host "CD image configured: $iso" -ForegroundColor Green
}

if(!$systemCnf -and !$iso){
    throw 'No SYSTEM.CNF or ISO was found. Keep the original disc image or extracted disc files in the game folder, or place the multipart RAR volumes there and run this command again.'
}

$report=[ordered]@{
    prepared_at=(Get-Date -Format o)
    game_root=$GameRoot
    extracted_archive=if($archive){$archive.FullName}else{$null}
    extraction_performed=$extracted
    seven_zip=$sevenZip
    system_cnf=$systemCnf
    cd_root=if($systemCnf){Split-Path $systemCnf -Parent}else{$null}
    iso=$iso
    cd_root_sidecar=if(Test-Path $cdRootSidecar){$cdRootSidecar}else{$null}
    cd_image_sidecar=if(Test-Path $cdImageSidecar){$cdImageSidecar}else{$null}
}
[IO.File]::WriteAllText((Join-Path $analysisDir 'game_data_prepared.json'),($report|ConvertTo-Json -Depth 5),(New-Object Text.UTF8Encoding($false)))

Write-Host ''
Write-Host 'Game data preparation complete.' -ForegroundColor Green
Write-Host 'No proprietary game data was added to Git.'


    $groups = @{}
    foreach($file in @(Get-ChildItem -LiteralPath $FirstVolume.DirectoryName -File -ErrorAction SilentlyContinue)){
        $vm = [regex]::Match($file.Name, $volumePattern, 'IgnoreCase')
        if(!$vm.Success){ continue }
        $part = [int]$vm.Groups['part'].Value
        if(!$groups.ContainsKey($part)){ $groups[$part] = New-Object System.Collections.Generic.List[object] }
        $groups[$part].Add($file)
    }

    if(!$groups.ContainsKey(1)){ throw "Multipart staging could not find part 1." }
    $maxPart = ($groups.Keys | Measure-Object -Maximum).Maximum
    for($part=1; $part -le $maxPart; $part++){
        if(!$groups.ContainsKey($part)){ throw "Multipart archive is missing part $part." }
    }

    $staging = Join-Path $FirstVolume.DirectoryName '.downhill_rar_staging'
    if(Test-Path -LiteralPath $staging){ Remove-Item -LiteralPath $staging -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $staging | Out-Null

    for($part=1; $part -le $maxPart; $part++){
        $digits = $part.ToString(('D' + $width))
        $canonicalName = $base + '.part' + $digits + '.rar'
        $choices = @($groups[$part])
        $source = $choices | Where-Object { $_.Name -ieq $canonicalName } | Select-Object -First 1
        if(!$source){ $source = $choices | Sort-Object Name | Select-Object -First 1 }

        $target = Join-Path $staging $canonicalName
        try {
            New-Item -ItemType HardLink -Path $target -Target $source.FullName -ErrorAction Stop | Out-Null
        }
        catch {
            throw ("Could not create a no-copy hardlink for multipart volume '{0}' -> '{1}'. Ensure the game folder is on NTFS. Error: {2}" -f $source.FullName,$target,$_.Exception.Message)
        }
    }

    return (Join-Path $staging ($base + '.part' + (1).ToString(('D' + $width)) + '.rar'))
}

$systemCnf = Find-SystemCnf $GameRoot $false
$iso = Find-Iso $GameRoot $false

if(!$systemCnf -and (Test-Path -LiteralPath $extractRoot)){ $systemCnf=Find-SystemCnf $extractRoot $true }
if(!$iso -and (Test-Path -LiteralPath $extractRoot)){ $iso=Find-Iso $extractRoot $true }

$archive=$null
$sevenZip=$null
$extracted=$false

if(!$systemCnf -and !$iso){
    $archive = Get-ChildItem -LiteralPath $GameRoot -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '(?i)\.part0*1\.rar$' } |
        Sort-Object Name | Select-Object -First 1

    if($archive){
        $sevenZip=Find-7Zip
        if(!$sevenZip){
            throw "Multipart RAR found ($($archive.Name)), but 7-Zip was not found. Install 7-Zip or place 7z.exe in PATH."
        }

        Write-Host "Testing multipart archive: $($archive.FullName)"
        & $sevenZip 't' $archive.FullName
        if($LASTEXITCODE -ne 0){throw "7-Zip archive test failed with exit code $LASTEXITCODE."}

        New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null
        Write-Host "Extracting local game data to: $extractRoot"
        & $sevenZip 'x' '-y' ('-o'+$extractRoot) $archive.FullName
        if($LASTEXITCODE -ne 0){throw "7-Zip extraction failed with exit code $LASTEXITCODE."}
        $extracted=$true

        $systemCnf=Find-SystemCnf $extractRoot $true
        $iso=Find-Iso $extractRoot $true
    }
}

if($systemCnf){
    $root=Split-Path $systemCnf -Parent
    Write-Sidecar $cdRootSidecar $root
    Write-Host "CD root configured: $root" -ForegroundColor Green
}
if($iso){
    Write-Sidecar $cdImageSidecar $iso
    Write-Host "CD image configured: $iso" -ForegroundColor Green
}

if(!$systemCnf -and !$iso){
    throw 'No SYSTEM.CNF or ISO was found. Keep the original disc image or extracted disc files in the game folder, or place the multipart RAR volumes there and run this command again.'
}

$report=[ordered]@{
    prepared_at=(Get-Date -Format o)
    game_root=$GameRoot
    extracted_archive=if($archive){$archive.FullName}else{$null}
    extraction_performed=$extracted
    seven_zip=$sevenZip
    system_cnf=$systemCnf
    cd_root=if($systemCnf){Split-Path $systemCnf -Parent}else{$null}
    iso=$iso
    cd_root_sidecar=if(Test-Path $cdRootSidecar){$cdRootSidecar}else{$null}
    cd_image_sidecar=if(Test-Path $cdImageSidecar){$cdImageSidecar}else{$null}
}
[IO.File]::WriteAllText((Join-Path $analysisDir 'game_data_prepared.json'),($report|ConvertTo-Json -Depth 5),(New-Object Text.UTF8Encoding($false)))

Write-Host ''
Write-Host 'Game data preparation complete.' -ForegroundColor Green
Write-Host 'No proprietary game data was added to Git.'
