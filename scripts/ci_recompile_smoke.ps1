param(
    [string]$Ps2RecompRoot = "_ci/PS2Recomp",
    [string]$BuildRoot = "_ci/build"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Ps2RecompRoot = [IO.Path]::GetFullPath($Ps2RecompRoot)
$BuildRoot = [IO.Path]::GetFullPath($BuildRoot)
$SmokeRoot = Join-Path (Split-Path $BuildRoot -Parent) "smoke"
$ElfPath = Join-Path $SmokeRoot "SCUS_SMOKE.ELF"
$ConfigPath = Join-Path $SmokeRoot "smoke.toml"
$MapPath = Join-Path $SmokeRoot "smoke.functions.csv"
$RunnerDir = Join-Path $Ps2RecompRoot "ps2xRuntime\src\runner"
$RuntimeInclude = Join-Path $Ps2RecompRoot "ps2xRuntime\include"

New-Item -ItemType Directory -Force -Path $SmokeRoot | Out-Null

function Find-BuiltTool {
    param([string]$Name)
    $hit = Get-ChildItem -LiteralPath $BuildRoot -Recurse -File -Filter $Name |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (!$hit) { throw "Missing built tool: $Name" }
    return $hit.FullName
}

function Invoke-Native {
    param([string]$Exe, [Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
    Write-Host ("> " + $Exe + " " + ($Arguments -join " "))
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Command failed ($LASTEXITCODE): $Exe" }
}

function Set-TomlScalar {
    param([string]$Text, [string]$Key, [string]$Value)
    $pattern = "(?m)^" + [regex]::Escape($Key) + "\s*=.*$"
    if (![regex]::IsMatch($Text, $pattern)) { throw "Missing TOML key: $Key" }
    return [regex]::Replace($Text, $pattern, ($Key + " = " + $Value), 1)
}

function Ensure-TomlArrayEntries {
    param([string]$Text, [string]$Key, [string[]]$Entries)
    $pattern = "(?ms)(^" + [regex]::Escape($Key) + "\s*=\s*\[\s*\r?\n)(.*?)(^\s*\])"
    $match = [regex]::Match($Text, $pattern)
    if (!$match.Success) { throw "Missing TOML array: $Key" }
    $body = $match.Groups[2].Value
    foreach ($entry in $Entries) {
        $quoted = '"' + $entry + '"'
        if ($body -notmatch [regex]::Escape($quoted)) {
            $body += "  " + $quoted + "," + [Environment]::NewLine
        }
    }
    return $Text.Substring(0,$match.Index) +
        $match.Groups[1].Value + $body + $match.Groups[3].Value +
        $Text.Substring($match.Index + $match.Length)
}

# Build a minimal little-endian ELF32/MIPS executable with one RX PT_LOAD.
$stream = [IO.File]::Open($ElfPath, [IO.FileMode]::Create, [IO.FileAccess]::Write)
$writer = New-Object IO.BinaryWriter($stream)
try {
    [byte[]]$ident = @(0x7F,0x45,0x4C,0x46,1,1,1,0,0,0,0,0,0,0,0,0)
    $writer.Write($ident)
    $writer.Write([uint16]2)            # ET_EXEC
    $writer.Write([uint16]8)            # EM_MIPS
    $writer.Write([uint32]1)
    $writer.Write([uint32]0x00100000)   # entry
    $writer.Write([uint32]0x34)         # phoff
    $writer.Write([uint32]0)            # shoff
    $writer.Write([uint32]0)
    $writer.Write([uint16]52)
    $writer.Write([uint16]32)
    $writer.Write([uint16]1)
    $writer.Write([uint16]40)
    $writer.Write([uint16]0)
    $writer.Write([uint16]0)

    $writer.Write([uint32]1)            # PT_LOAD
    $writer.Write([uint32]0x1000)
    $writer.Write([uint32]0x00100000)
    $writer.Write([uint32]0x00100000)
    $writer.Write([uint32]20)
    $writer.Write([uint32]20)
    $writer.Write([uint32]5)            # RX
    $writer.Write([uint32]0x1000)

    while ($stream.Position -lt 0x1000) { $writer.Write([byte]0) }
    $writer.Write([uint32]0x2402002A)   # addiu v0, zero, 42
    $writer.Write([uint32]0x03E00008)   # jr ra
    $writer.Write([uint32]0x00000000)   # delay-slot nop
    $writer.Write([uint32]0x03E00008)   # second function: jr ra
    $writer.Write([uint32]0x00000000)   # second function delay-slot nop
}
finally {
    $writer.Dispose()
    $stream.Dispose()
}

[IO.File]::WriteAllText(
    $MapPath,
    "name,start,end,size`r`nsmoke_main,0x00100000,0x0010000C,12`r`nanonymous_pad_target,0x0010000C,0x00100014,8`r`n",
    (New-Object Text.UTF8Encoding($false))
)

$Analyzer = Find-BuiltTool "ps2_analyzer.exe"
$Recompiler = Find-BuiltTool "ps2_recomp.exe"

Invoke-Native $Analyzer $ElfPath $ConfigPath

$toml = Get-Content -Raw -LiteralPath $ConfigPath
$elfToml = $ElfPath.Replace("\", "/")
$runnerToml = $RunnerDir.Replace("\", "/")
$mapToml = $MapPath.Replace("\", "/")
$toml = Set-TomlScalar $toml "input" ('"' + $elfToml + '"')
$toml = Set-TomlScalar $toml "output" ('"' + $runnerToml + '"')
$toml = Set-TomlScalar $toml "ghidra_output" ('"' + $mapToml + '"')
$toml = Set-TomlScalar $toml "single_file_output" "true"
$toml = Ensure-TomlArrayEntries $toml "stubs" @("scePadRead@0x0010000C")
[IO.File]::WriteAllText($ConfigPath, $toml, (New-Object Text.UTF8Encoding($false)))

Get-ChildItem -LiteralPath $RunnerDir -Filter "*.cpp" -File | Remove-Item -Force
Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $RuntimeInclude "ps2_recompiled_functions.h")
Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $RuntimeInclude "ps2_recompiled_stubs.h")

Invoke-Native $Recompiler $ConfigPath

$required = @(
    (Join-Path $RunnerDir "ps2_recompiled_functions.cpp"),
    (Join-Path $RunnerDir "register_functions.cpp"),
    (Join-Path $RunnerDir "ps2_recompiled_functions.h"),
    (Join-Path $RunnerDir "ps2_recompiled_stubs.h")
)
foreach ($path in $required) {
    if (!(Test-Path -LiteralPath $path)) { throw "Recompiler did not generate: $path" }
}

$generated = Get-Content -Raw -LiteralPath (Join-Path $RunnerDir "ps2_recompiled_functions.cpp")
if ($generated -notmatch "2402002A|ADD32|42") {
    throw "Generated C++ does not contain recognizable output for the smoke function."
}

if ($generated -notmatch "ps2_stubs::scePadRead") {
    throw "Address-bound stub selector did not generate scePadRead for anonymous_pad_target."
}

$registration = Get-Content -Raw -LiteralPath (Join-Path $RunnerDir "register_functions.cpp")
if ($registration -notmatch "(?i)//\s*0x0*10000c\b") {
    throw "Address-bound stub target 0x0010000C is missing from the generated function table."
}

Copy-Item -Force (Join-Path $RunnerDir "ps2_recompiled_functions.h") (Join-Path $RuntimeInclude "ps2_recompiled_functions.h")
Copy-Item -Force (Join-Path $RunnerDir "ps2_recompiled_stubs.h") (Join-Path $RuntimeInclude "ps2_recompiled_stubs.h")

Write-Host "Synthetic ELF recompilation smoke test passed."
Write-Host "ELF: $ElfPath"
Write-Host "Config: $ConfigPath"
Write-Host "Generated: $RunnerDir"
