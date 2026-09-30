param(
    [string]$GameRoot = "",
    [string]$Out = ""
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
if(!$Out){$Out=Join-Path $RepoRoot 'analysis\local\game_data_inventory.json'}
New-Item -ItemType Directory -Force -Path (Split-Path ([IO.Path]::GetFullPath($Out)) -Parent)|Out-Null

$cdRoot=$null
$rootSidecar=Join-Path $GameRoot 'downhill_cd_root.txt'
if(Test-Path -LiteralPath $rootSidecar){
    $v=(Get-Content -LiteralPath $rootSidecar -TotalCount 1).Trim()
    if($v -and (Test-Path -LiteralPath $v -PathType Container)){$cdRoot=[IO.Path]::GetFullPath($v)}
}
if(!$cdRoot){
    foreach($candidate in @($GameRoot,(Join-Path $GameRoot 'game_data'))){
        if($candidate -and (Test-Path -LiteralPath (Join-Path $candidate 'SYSTEM.CNF'))){$cdRoot=[IO.Path]::GetFullPath($candidate);break}
    }
}

$iso=$null
$imageSidecar=Join-Path $GameRoot 'downhill_cd_image.txt'
if(Test-Path -LiteralPath $imageSidecar){
    $v=(Get-Content -LiteralPath $imageSidecar -TotalCount 1).Trim()
    if($v -and (Test-Path -LiteralPath $v -PathType Leaf)){$iso=[IO.Path]::GetFullPath($v)}
}

$boot2=$null
$fileCount=0
[int64]$totalBytes=0
$extensionRows=@()
$irxRows=@()
$moduleImages=@()
$topDirectories=@()
$mode='none'

if($cdRoot){
    $mode='extracted-root'
    $systemCnf=Join-Path $cdRoot 'SYSTEM.CNF'
    if(Test-Path -LiteralPath $systemCnf){
        foreach($line in Get-Content -LiteralPath $systemCnf){
            if($line -match '(?i)^\s*BOOT2\s*=\s*(.+?)\s*$'){$boot2=$Matches[1].Trim();break}
        }
    }

    $files=@(Get-ChildItem -LiteralPath $cdRoot -File -Recurse -ErrorAction Stop)
    $fileCount=$files.Count
    foreach($file in $files){$totalBytes+=[int64]$file.Length}

    $extensionRows=@(
        $files | Group-Object {
            $ext=$_.Extension.ToLowerInvariant()
            if($ext){$ext}else{'<none>'}
        } | Sort-Object -Property @{Expression='Count';Descending=$true}, Name | ForEach-Object {
            [pscustomobject][ordered]@{extension=$_.Name;count=$_.Count}
        }
    )

    $irxRows=@(
        $files | Where-Object {$_.Extension -ieq '.irx'} | Sort-Object FullName | ForEach-Object {
            $rel=$_.FullName.Substring($cdRoot.Length).TrimStart('\','/')
            [pscustomobject][ordered]@{path=$rel;bytes=[int64]$_.Length}
        }
    )

    $moduleImages=@(
        $files | Where-Object {
            $_.Extension -ieq '.img' -or $_.Name -match '(?i)^IOPRP.*\.IMG$'
        } | Sort-Object FullName | ForEach-Object {
            $rel=$_.FullName.Substring($cdRoot.Length).TrimStart('\','/')
            [pscustomobject][ordered]@{path=$rel;bytes=[int64]$_.Length}
        }
    )

    $dirCounts=@{}
    foreach($row in $irxRows){
        $dir=Split-Path $row.path -Parent
        if(!$dir){$dir='<root>'}
        if(!$dirCounts.ContainsKey($dir)){$dirCounts[$dir]=0}
        $dirCounts[$dir]++
    }
    $topDirectories=@(
        $dirCounts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 16 | ForEach-Object {
            [pscustomobject][ordered]@{directory=[string]$_.Key;irx_count=[int]$_.Value}
        }
    )
}
elseif($iso){
    $mode='iso-only'
}

$report=[ordered]@{
    generated=(Get-Date -Format o)
    game_root=$GameRoot
    inventory_mode=$mode
    cd_root=$cdRoot
    iso=$iso
    iso_bytes=if($iso){[int64](Get-Item -LiteralPath $iso).Length}else{$null}
    boot2=$boot2
    file_count=$fileCount
    total_bytes=$totalBytes
    extension_counts=$extensionRows
    irx_count=@($irxRows).Count
    irx_files=$irxRows
    module_image_count=@($moduleImages).Count
    module_images=$moduleImages
    irx_directories=$topDirectories
    notes=if($mode -eq 'iso-only'){'ISO is configured but no extracted CD root is available; IRX inventory requires extracted files.'}else{$null}
}

[IO.File]::WriteAllText([IO.Path]::GetFullPath($Out),($report|ConvertTo-Json -Depth 7),(New-Object Text.UTF8Encoding($false)))
Write-Host ('Game-data inventory: mode={0}, files={1}, IRX={2}, module images={3}' -f $mode,$fileCount,@($irxRows).Count,@($moduleImages).Count)
Write-Host ('Report: '+[IO.Path]::GetFullPath($Out))
exit 0
