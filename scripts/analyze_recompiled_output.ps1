param(
    [Parameter(Mandatory=$true)][string]$Config,
    [Parameter(Mandatory=$true)][string]$GeneratedDir,
    [Parameter(Mandatory=$true)][string]$Out
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Config = (Resolve-Path -LiteralPath $Config).Path
$GeneratedDir = (Resolve-Path -LiteralPath $GeneratedDir).Path

$functionsHeader = Join-Path $GeneratedDir "ps2_recompiled_functions.h"
$stubsHeader = Join-Path $GeneratedDir "ps2_recompiled_stubs.h"
$combinedFunctionsCpp = Join-Path $GeneratedDir "ps2_recompiled_functions.cpp"
$registrationCpp = Join-Path $GeneratedDir "register_functions.cpp"

foreach ($path in @($functionsHeader,$stubsHeader,$registrationCpp)) {
    if (!(Test-Path -LiteralPath $path)) { throw "Missing generated artifact: $path" }
}

$generatedCppFiles = @()
if (Test-Path -LiteralPath $combinedFunctionsCpp) {
    $generatedCppFiles = @((Get-Item -LiteralPath $combinedFunctionsCpp))
    $outputMode = "single-file"
}
else {
    $generatedCppFiles = @(
        Get-ChildItem -LiteralPath $GeneratedDir -Filter "*.cpp" -File |
        Where-Object {
            $_.Name -ne "register_functions.cpp" -and
            $_.Name -ne "downhill_domination_overrides.cpp"
        } |
        Sort-Object Name
    )
    $outputMode = "multi-file"
}

if ($generatedCppFiles.Count -eq 0) {
    throw "No generated function C++ files were found in $GeneratedDir"
}

$toml = Get-Content -Raw -LiteralPath $Config
$fh = Get-Content -Raw -LiteralPath $functionsHeader
$sh = Get-Content -Raw -LiteralPath $stubsHeader
$reg = Get-Content -Raw -LiteralPath $registrationCpp

function Count-Matches([string]$Text,[string]$Pattern) {
    return ([regex]::Matches($Text,$Pattern,[Text.RegularExpressions.RegexOptions]::Multiline)).Count
}

function Get-TomlArrayCount([string]$Text,[string]$Key) {
    $m=[regex]::Match($Text,"(?ms)^"+[regex]::Escape($Key)+"\s*=\s*\[(.*?)^\s*\]")
    if(!$m.Success){ return 0 }
    return ([regex]::Matches($m.Groups[1].Value,'"[^"]+"')).Count
}

$tableBase = $null
$tableEnd = $null
$slotCount = $null
$m=[regex]::Match($reg,'g_ps2RecompiledFunctionTableBase\s*=\s*(0x[0-9A-Fa-f]+)u')
if($m.Success){$tableBase=$m.Groups[1].Value.ToUpperInvariant()}
$m=[regex]::Match($reg,'g_ps2RecompiledFunctionTableEnd\s*=\s*(0x[0-9A-Fa-f]+)u')
if($m.Success){$tableEnd=$m.Groups[1].Value.ToUpperInvariant()}
$m=[regex]::Match($reg,'g_ps2RecompiledFunctionTableSlotCount\s*=\s*([0-9]+)u')
if($m.Success){$slotCount=[int64]$m.Groups[1].Value}

$critical=@('0x0010A008','0x001FB6C0','0x002451B0','0x00246FA0','0x00254050','0x0025C440')
$criticalPresence=[ordered]@{}
foreach($addr in $critical){
    $body=$addr.Substring(2).TrimStart([char]'0')
    if(!$body){$body='0'}
    $criticalPresence[$addr]=[regex]::IsMatch($reg,"(?i)//\s*0x0*"+[regex]::Escape($body)+"\b")
}

$todoCounts = @{}
[int64]$generatedCppBytes = 0
$generatedCppHashes = New-Object System.Collections.Generic.List[object]
$todoNamedOccurrences = 0

foreach ($file in $generatedCppFiles) {
    $text = Get-Content -Raw -LiteralPath $file.FullName
    $generatedCppBytes += [int64]$file.Length
    $matches = [regex]::Matches($text,'TODO_NAMED\(\"([^\"]+)\"')
    $todoNamedOccurrences += $matches.Count
    foreach ($match in $matches) {
        $name = $match.Groups[1].Value
        if (!$todoCounts.ContainsKey($name)) { $todoCounts[$name] = 0 }
        $todoCounts[$name]++
    }

    $generatedCppHashes.Add([ordered]@{
        file = $file.Name
        bytes = [int64]$file.Length
        sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    })
}

$todoNames=@(
    $todoCounts.GetEnumerator() |
    Sort-Object Value -Descending |
    Select-Object -First 50 |
    ForEach-Object { [ordered]@{ name=$_.Key; count=[int]$_.Value } }
)

$report=[ordered]@{
    config=$Config
    generated_dir=$GeneratedDir
    generated_at=(Get-Date -Format o)
    toml=[ordered]@{
        stubs=Get-TomlArrayCount $toml 'stubs'
        entry_points=Get-TomlArrayCount $toml 'entry_points'
        skip=Get-TomlArrayCount $toml 'skip'
        mmio_entries=Count-Matches $toml '^\"0x[0-9A-Fa-f]+\"\s*=\s*\"0x[0-9A-Fa-f]+\"'
        jump_tables=Count-Matches $toml '^\[\[jump_tables\.table\]\]'
        patch_instructions=Count-Matches $toml '^\s*\{\s*address\s*=\s*\"0x[0-9A-Fa-f]+\"'
        ghidra_enabled=([regex]::IsMatch($toml,'(?m)^ghidra_output\s*=\s*\"[^\"]+\"'))
    }
    generated=[ordered]@{
        function_declarations=Count-Matches $fh '^void\s+[A-Za-z_][A-Za-z0-9_]*\s*\('
        stub_declarations=Count-Matches $sh '^void\s+[A-Za-z_][A-Za-z0-9_]*\s*\('
        output_mode=$outputMode
        cpp_file_count=$generatedCppFiles.Count
        todo_named_occurrences=$todoNamedOccurrences
        registered_entries=Count-Matches $reg '^\s*g_ps2RecompiledFunctionTable\[[0-9]+\]\s*='
        table_base=$tableBase
        table_end=$tableEnd
        table_slot_count=$slotCount
        cpp_bytes=$generatedCppBytes
        cpp_files=$generatedCppHashes
        registration_bytes=(Get-Item -LiteralPath $registrationCpp).Length
        registration_sha256=(Get-FileHash -LiteralPath $registrationCpp -Algorithm SHA256).Hash
    }
    critical_addresses=$criticalPresence
    top_todo_named=$todoNames
}

$json=$report | ConvertTo-Json -Depth 8
[IO.File]::WriteAllText([IO.Path]::GetFullPath($Out),$json,(New-Object Text.UTF8Encoding($false)))

Write-Host "Static recompilation report: $Out"
Write-Host ("Functions: {0}; stubs: {1}; registered: {2}; TODO_NAMED: {3}" -f `
    $report.generated.function_declarations,
    $report.generated.stub_declarations,
    $report.generated.registered_entries,
    $report.generated.todo_named_occurrences)
