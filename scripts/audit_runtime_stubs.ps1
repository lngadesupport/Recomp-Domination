param(
    [Parameter(Mandatory=$true)][string]$Config,
    [Parameter(Mandatory=$true)][string]$Ps2RecompRoot,
    [Parameter(Mandatory=$true)][string]$Out
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$Config=(Resolve-Path -LiteralPath $Config).Path
$Ps2RecompRoot=(Resolve-Path -LiteralPath $Ps2RecompRoot).Path
$runtimeSrc=Join-Path $Ps2RecompRoot 'ps2xRuntime\src\lib'
if(!(Test-Path -LiteralPath $runtimeSrc)){throw "Runtime source directory not found: $runtimeSrc"}

$toml=Get-Content -Raw -LiteralPath $Config
$m=[regex]::Match($toml,'(?ms)^stubs\s*=\s*\[(.*?)^\s*\]')
$selectors=@()
if($m.Success){$selectors=@([regex]::Matches($m.Groups[1].Value,'\"([^\"]+)\"')|ForEach-Object{$_.Groups[1].Value})}

$names=@($selectors|ForEach-Object{($_ -split '@',2)[0]}|Where-Object{$_}|Sort-Object -Unique)
$sourceFiles=@(Get-ChildItem -LiteralPath $runtimeSrc -Filter '*.cpp' -File -Recurse -ErrorAction SilentlyContinue)
$sources=@{}
foreach($file in $sourceFiles){$sources[$file.FullName]=Get-Content -Raw -LiteralPath $file.FullName}

$rows=New-Object System.Collections.Generic.List[object]
foreach($name in $names){
    $aliases=@($name)
    if($name.StartsWith('_') -and $name.Length -gt 1){$aliases+= $name.Substring(1)}
    elseif(!$name.StartsWith('_')){$aliases+=('_'+$name)}

    $found=$false
    $status='not-found'
    $sourcePath=$null
    $resolvedName=$null
    foreach($alias in $aliases|Select-Object -Unique){
        $pattern='(?m)^\s*void\s+'+[regex]::Escape($alias)+'\s*\('
        foreach($entry in $sources.GetEnumerator()){
            $match=[regex]::Match($entry.Value,$pattern)
            if(!$match.Success){continue}
            $found=$true
            $sourcePath=$entry.Key
            $resolvedName=$alias
            $start=$match.Index
            $next=[regex]::Match($entry.Value.Substring([Math]::Min($entry.Value.Length,$start+$match.Length)),'(?m)^\s*void\s+[A-Za-z_][A-Za-z0-9_]*\s*\(')
            $end=if($next.Success){$start+$match.Length+$next.Index}else{[Math]::Min($entry.Value.Length,$start+5000)}
            $body=$entry.Value.Substring($start,[Math]::Max(0,$end-$start))
            if($body -match 'TODO_NAMED\s*\(' -or $body -match '(?m)\bTODO\s*\('){$status='todo'}else{$status='implemented'}
            break
        }
        if($found){break}
    }

    $rows.Add([pscustomobject][ordered]@{
        selector=($selectors|Where-Object{($_ -split '@',2)[0] -eq $name}|Select-Object -First 1)
        requested_name=$name
        resolved_source_name=$resolvedName
        status=$status
        source=if($sourcePath){$sourcePath.Substring($Ps2RecompRoot.Length).TrimStart('\','/')}else{$null}
    })
}

$implemented=@($rows|Where-Object status -eq 'implemented').Count
$todo=@($rows|Where-Object status -eq 'todo').Count
$missing=@($rows|Where-Object status -eq 'not-found').Count
$report=[ordered]@{
    config=$Config
    ps2recomp_root=$Ps2RecompRoot
    audited_stub_count=$rows.Count
    implemented=$implemented
    todo=$todo
    not_found=$missing
    stubs=@($rows|Sort-Object status,requested_name)
}
[IO.File]::WriteAllText([IO.Path]::GetFullPath($Out),($report|ConvertTo-Json -Depth 7),(New-Object Text.UTF8Encoding($false)))
Write-Host ("Runtime stub audit: implemented={0}, todo={1}, not-found={2}" -f $implemented,$todo,$missing)
Write-Host ("Report: "+[IO.Path]::GetFullPath($Out))
