param(
    [Parameter(Mandatory=$true)][string]$Config,
    [Parameter(Mandatory=$true)][string]$Ps2RecompRoot,
    [Parameter(Mandatory=$true)][string]$Out
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Config = (Resolve-Path -LiteralPath $Config).Path
$Ps2RecompRoot = (Resolve-Path -LiteralPath $Ps2RecompRoot).Path
$runtimeSrc = Join-Path $Ps2RecompRoot "ps2xRuntime\src\lib"
if (!(Test-Path -LiteralPath $runtimeSrc)) { throw "Runtime source directory not found: $runtimeSrc" }

$toml = Get-Content -Raw -LiteralPath $Config
$stubMatch = [regex]::Match($toml, '(?ms)(^stubs\s*=\s*\[\s*\r?\n)(.*?)(^\s*\])')
if (!$stubMatch.Success) { throw "Config has no stubs array: $Config" }

$selectors = @(
    [regex]::Matches($stubMatch.Groups[2].Value, '"([^"]+)"') |
        ForEach-Object { $_.Groups[1].Value }
)

$sourceFiles = @(Get-ChildItem -LiteralPath $runtimeSrc -Filter "*.cpp" -File -Recurse -ErrorAction SilentlyContinue)
$sources = @{}
foreach ($file in $sourceFiles) {
    $sources[$file.FullName] = Get-Content -Raw -LiteralPath $file.FullName
}

function Get-HandlerStatus {
    param([string]$Name)

    $aliases = @($Name)
    if ($Name.StartsWith("_") -and $Name.Length -gt 1) {
        $aliases += $Name.Substring(1)
    }
    elseif (!$Name.StartsWith("_")) {
        $aliases += ("_" + $Name)
    }

    foreach ($alias in ($aliases | Select-Object -Unique)) {
        $pattern = '(?m)^\s*void\s+' + [regex]::Escape($alias) + '\s*\('
        foreach ($entry in $sources.GetEnumerator()) {
            $match = [regex]::Match($entry.Value, $pattern)
            if (!$match.Success) { continue }

            $start = $match.Index
            $afterStart = [Math]::Min($entry.Value.Length, $start + $match.Length)
            $tail = $entry.Value.Substring($afterStart)
            $next = [regex]::Match($tail, '(?m)^\s*void\s+[A-Za-z_][A-Za-z0-9_]*\s*\(')
            $end = if ($next.Success) { $afterStart + $next.Index } else { [Math]::Min($entry.Value.Length, $start + 5000) }
            $body = $entry.Value.Substring($start, [Math]::Max(0, $end - $start))
            $status = if ($body -match 'TODO_NAMED\s*\(' -or $body -match '(?m)\bTODO\s*\(') { "todo" } else { "implemented" }

            return [pscustomobject]@{
                status = $status
                resolved_name = $alias
                source = $entry.Key.Substring($Ps2RecompRoot.Length).TrimStart("\", "/")
            }
        }
    }

    return [pscustomobject]@{
        status = "not-found"
        resolved_name = $null
        source = $null
    }
}

$safe = New-Object System.Collections.Generic.List[string]
$unsafe = New-Object System.Collections.Generic.List[object]
$rows = New-Object System.Collections.Generic.List[object]

foreach ($selector in $selectors) {
    $parts = $selector -split "@", 2
    $name = $parts[0]
    $address = if ($parts.Count -gt 1 -and $parts[1] -match '(?i)^0x[0-9a-f]{1,8}$') { $parts[1] } else { $null }
    $result = Get-HandlerStatus $name

    $row = [pscustomobject][ordered]@{
        selector = $selector
        name = $name
        address = $address
        status = $result.status
        resolved_name = $result.resolved_name
        source = $result.source
    }
    $rows.Add($row)

    if ($result.status -eq "implemented") {
        $safe.Add($selector)
    }
    else {
        $unsafe.Add($row)
    }
}

$safe = @($safe | Sort-Object -Unique)

# Rewrite stubs to contain only handlers with a concrete non-TODO implementation.
$stubLines = New-Object System.Collections.Generic.List[string]
foreach ($selector in $safe) {
    $stubLines.Add(('  "{0}",' -f $selector))
}
$newStubBody = if ($stubLines.Count -gt 0) { ($stubLines -join [Environment]::NewLine) + [Environment]::NewLine } else { "" }
$toml = $toml.Substring(0, $stubMatch.Index) +
        $stubMatch.Groups[1].Value +
        $newStubBody +
        $stubMatch.Groups[3].Value +
        $toml.Substring($stubMatch.Index + $stubMatch.Length)

# Unsafe exact selectors remain callable guest functions instead of being
# replaced by an incomplete host handler.
$unsafeEntries = @(
    $unsafe |
        Where-Object { $_.address } |
        ForEach-Object { $_.selector } |
        Sort-Object -Unique
)

if ($unsafeEntries.Count -gt 0) {
    $entryMatch = [regex]::Match($toml, '(?ms)(^entry_points\s*=\s*\[\s*\r?\n)(.*?)(^\s*\])')
    if (!$entryMatch.Success) { throw "Config has no entry_points array: $Config" }

    $entryBody = $entryMatch.Groups[2].Value
    foreach ($selector in $unsafeEntries) {
        $quoted = '"' + $selector + '"'
        if ($entryBody -notmatch [regex]::Escape($quoted)) {
            $entryBody += ('  "{0}",' -f $selector) + [Environment]::NewLine
        }
    }

    $toml = $toml.Substring(0, $entryMatch.Index) +
            $entryMatch.Groups[1].Value +
            $entryBody +
            $entryMatch.Groups[3].Value +
            $toml.Substring($entryMatch.Index + $entryMatch.Length)
}

[IO.File]::WriteAllText($Config, $toml, (New-Object Text.UTF8Encoding($false)))

$report = [ordered]@{
    config = $Config
    ps2recomp_root = $Ps2RecompRoot
    original_stub_count = $selectors.Count
    safe_stub_count = $safe.Count
    unsafe_stub_count = $unsafe.Count
    unsafe_exact_entry_points_preserved = $unsafeEntries
    stubs = @($rows | Sort-Object status,name)
}

[IO.File]::WriteAllText(
    [IO.Path]::GetFullPath($Out),
    ($report | ConvertTo-Json -Depth 7),
    (New-Object Text.UTF8Encoding($false))
)

Write-Host ("Runtime stub filter: safe={0}, guest-preserved={1}" -f $safe.Count,$unsafe.Count)
foreach ($row in $unsafe) {
    Write-Host ("  guest-preserved: {0} ({1})" -f $row.selector,$row.status) -ForegroundColor Yellow
}
Write-Host ("Report: " + [IO.Path]::GetFullPath($Out))
