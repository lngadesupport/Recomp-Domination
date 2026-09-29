param(
    [string]$GameRoot = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$PinnedPs2Recomp = "75d729ce40d7eed9649fd4bb05628dee520f3d0c"
$ExpectedSize = 1691684
$ExpectedSha256 = "ADFDA7B73A8F05FB20A3F0F318772E9D3797FD4D6C0A6C0078AE392DF0F0CF0C"
$ExpectedPcsx2Crc = [Convert]::ToUInt32("5AE01D98", 16)
$ExpectedEntry = [uint32]0x0010A008

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ThirdPartyRoot = Join-Path $RepoRoot "third_party"
$Ps2RecompRoot = Join-Path $ThirdPartyRoot "PS2Recomp"
$BuildRoot = Join-Path $Ps2RecompRoot "out\build-downhill"
$ConfigDir = Join-Path $RepoRoot "config"
$AnalysisDir = Join-Path $RepoRoot "analysis"
$LocalAnalysisDir = Join-Path $AnalysisDir "local"
$LogsDir = Join-Path $RepoRoot "logs"
$AutoConfig = Join-Path $ConfigDir "downhill.auto.toml"
$GhidraCsv = Join-Path $AnalysisDir "SCUS_971.77.functions.csv"
$OverrideSource = Join-Path $RepoRoot "src\downhill_domination_overrides.cpp"

New-Item -ItemType Directory -Force -Path $ThirdPartyRoot | Out-Null
New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
New-Item -ItemType Directory -Force -Path $LocalAnalysisDir | Out-Null
New-Item -ItemType Directory -Force -Path $LogsDir | Out-Null

$Transcript = Join-Path $LogsDir ("build_downhill_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".log")
Start-Transcript -Path $Transcript -Force | Out-Null

function Invoke-Native {
    param(
        [Parameter(Mandatory=$true)][string]$Exe,
        [Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments
    )

    Write-Host ""
    Write-Host ("> " + $Exe + " " + ($Arguments -join " ")) -ForegroundColor DarkGray
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code $LASTEXITCODE : $Exe"
    }
}

function Require-Command {
    param([string]$Name)

    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if (!$cmd) {
        throw "Missing prerequisite '$Name'. Install it and reopen the terminal."
    }

    return $cmd.Source
}

function Require-MsvcToolchain {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"

    if (!(Test-Path -LiteralPath $vswhere)) {
        throw "Visual Studio Installer/vswhere was not found. Install Visual Studio 2022 or Build Tools 2022 with Desktop development with C++."
    }

    $installation = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath

    if ($LASTEXITCODE -ne 0 -or !$installation) {
        throw "MSVC x64 tools were not found. Add the Desktop development with C++ workload in Visual Studio Installer."
    }

    Write-Host ("      MSVC toolchain: " + $installation) -ForegroundColor DarkGray
}

function Hex32 {
    param([uint32]$Value)
    return ("0x{0:X8}" -f $Value)
}

function Read-U32 {
    param([byte[]]$Data, [int]$Offset)

    if ($Offset -lt 0 -or ($Offset + 4) -gt $Data.Length) {
        throw "U32 read outside ELF at file offset $Offset"
    }

    return [BitConverter]::ToUInt32($Data, $Offset)
}

function Get-Pcsx2ElfCrc {
    param([byte[]]$Data)

    [uint32]$crc = 0
    [int]$count = [math]::Floor($Data.Length / 4)

    for ($i = 0; $i -lt $count; $i++) {
        [uint32]$word = [BitConverter]::ToUInt32($Data, $i * 4)
        $crc = [uint32]($crc -bxor $word)
    }

    return $crc
}

function Get-Crc32Ieee {
    param([byte[]]$Data)

    [uint32]$poly = [Convert]::ToUInt32("EDB88320", 16)
    [uint32]$crc = [Convert]::ToUInt32("FFFFFFFF", 16)
    [uint32[]]$table = New-Object 'UInt32[]' 256

    for ($i = 0; $i -lt 256; $i++) {
        [uint32]$value = $i

        for ($j = 0; $j -lt 8; $j++) {
            if (($value -band 1) -ne 0) {
                $value = [uint32](($value -shr 1) -bxor $poly)
            }
            else {
                $value = [uint32]($value -shr 1)
            }
        }

        $table[$i] = $value
    }

    foreach ($byte in $Data) {
        $index = [int](($crc -bxor [uint32]$byte) -band 0xFF)
        $crc = [uint32]($table[$index] -bxor ($crc -shr 8))
    }

    return [uint32]($crc -bxor [Convert]::ToUInt32("FFFFFFFF", 16))
}

function Resolve-GameRoot {
    param([string]$Requested)

    if ($Requested) {
        $candidate = [IO.Path]::GetFullPath($Requested)

        if (Test-Path -LiteralPath (Join-Path $candidate "SCUS_971.77")) {
            return $candidate
        }

        throw "SCUS_971.77 was not found under '$candidate'."
    }

    $repoParent = Split-Path $RepoRoot -Parent
    $candidates = @($repoParent, "D:\Recomp Domination") | Select-Object -Unique

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath (Join-Path $candidate "SCUS_971.77"))) {
            return [IO.Path]::GetFullPath($candidate)
        }
    }

    throw "Could not locate SCUS_971.77. Run BUILD_DOWNHILL.cmd with the game folder as its first argument."
}

function Validate-Elf {
    param([string]$ElfPath)

    Write-Host "[1/7] Validating SCUS_971.77..." -ForegroundColor Cyan

    $file = Get-Item -LiteralPath $ElfPath

    if ($file.Length -ne $ExpectedSize) {
        throw "Unexpected ELF size: $($file.Length), expected $ExpectedSize."
    }

    $sha = (Get-FileHash -LiteralPath $ElfPath -Algorithm SHA256).Hash.ToUpperInvariant()

    if ($sha -ne $ExpectedSha256) {
        throw "SHA-256 mismatch. Got $sha."
    }

    [byte[]]$bytes = [IO.File]::ReadAllBytes($ElfPath)

    if ($bytes[0] -ne 0x7F -or $bytes[1] -ne 0x45 -or $bytes[2] -ne 0x4C -or $bytes[3] -ne 0x46) {
        throw "Invalid ELF magic."
    }

    if ($bytes[4] -ne 1 -or $bytes[5] -ne 1) {
        throw "Expected ELF32 little-endian."
    }

    [uint16]$machine = [BitConverter]::ToUInt16($bytes, 18)
    [uint32]$entry = [BitConverter]::ToUInt32($bytes, 24)
    [uint32]$phoff = [BitConverter]::ToUInt32($bytes, 28)
    [uint16]$phentsize = [BitConverter]::ToUInt16($bytes, 42)
    [uint16]$phnum = [BitConverter]::ToUInt16($bytes, 44)

    if ($machine -ne 8) {
        throw "Expected EM_MIPS (8), got $machine."
    }

    if ($entry -ne $ExpectedEntry) {
        throw "Unexpected entry: $(Hex32 $entry)."
    }

    if ($phnum -ne 1) {
        throw "Expected one program header, got $phnum."
    }

    if ($phentsize -lt 32) {
        throw "Unexpected program header entry size: $phentsize."
    }

    [int]$ph = [int]$phoff
    [uint32]$ptType = Read-U32 $bytes ($ph + 0)
    [uint32]$ptOffset = Read-U32 $bytes ($ph + 4)
    [uint32]$ptVaddr = Read-U32 $bytes ($ph + 8)
    [uint32]$ptPaddr = Read-U32 $bytes ($ph + 12)
    [uint32]$ptFilesz = Read-U32 $bytes ($ph + 16)
    [uint32]$ptMemsz = Read-U32 $bytes ($ph + 20)
    [uint32]$ptFlags = Read-U32 $bytes ($ph + 24)
    [uint32]$ptAlign = Read-U32 $bytes ($ph + 28)

    if ($ptType -ne 1 -or
        $ptOffset -ne 0x00001000 -or
        $ptVaddr -ne 0x0010A000 -or
        $ptPaddr -ne 0x0010A000 -or
        $ptFilesz -ne 0x00193CF0 -or
        $ptMemsz -ne 0x00796400 -or
        $ptFlags -ne 0x00000007 -or
        $ptAlign -ne 0x00001000) {
        throw "PT_LOAD geometry does not match the validated retail build."
    }

    function Read-GuestWord {
        param([uint32]$Address)

        if ($Address -lt $ptVaddr -or ([uint64]$Address + 4) -gt ([uint64]$ptVaddr + $ptFilesz)) {
            throw "Guest address $(Hex32 $Address) is outside the file-backed PT_LOAD."
        }

        $fileOffset = [int]([uint64]$ptOffset + ([uint64]$Address - $ptVaddr))
        return [uint32](Read-U32 $bytes $fileOffset)
    }

    $anchors = [ordered]@{
        "0x0025C5A0" = [uint32]0x0C097110
        "0x0024520C" = [uint32]0x0C095014
        "0x001B6740" = [uint32]0x0C07EDB0
        "0x00243D34" = [uint32]0x30420001
    }

    foreach ($pair in $anchors.GetEnumerator()) {
        [uint32]$address = [Convert]::ToUInt32($pair.Key.Substring(2), 16)
        [uint32]$actual = Read-GuestWord $address

        if ($actual -ne [uint32]$pair.Value) {
            throw "Anchor $($pair.Key) mismatch: got $(Hex32 $actual), expected $(Hex32 ([uint32]$pair.Value))."
        }
    }

    [uint32]$pcsx2crc = Get-Pcsx2ElfCrc $bytes

    if ($pcsx2crc -ne $ExpectedPcsx2Crc) {
        throw "PCSX2 ELF CRC mismatch: got $(Hex32 $pcsx2crc)."
    }

    [uint32]$crc32 = Get-Crc32Ieee $bytes

    $identity = [ordered]@{
        file = $ElfPath
        size_bytes = $file.Length
        sha256 = $sha
        entry = Hex32 $entry
        machine = $machine
        pcsx2_elf_crc = Hex32 $pcsx2crc
        crc32_ieee = Hex32 $crc32
        pt_load = [ordered]@{
            offset = Hex32 $ptOffset
            vaddr = Hex32 $ptVaddr
            paddr = Hex32 $ptPaddr
            filesz = Hex32 $ptFilesz
            memsz = Hex32 $ptMemsz
            flags = Hex32 $ptFlags
            align = Hex32 $ptAlign
        }
        anchors_valid = $true
    }

    $identityPath = Join-Path $LocalAnalysisDir "SCUS_971.77.identity.json"
    $identity | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $identityPath -Encoding UTF8

    Write-Host "      Build identity OK; CRC32/IEEE = $(Hex32 $crc32)" -ForegroundColor Green
}

function Set-TomlScalar {
    param([string]$Text, [string]$Key, [string]$Value)

    $pattern = "(?m)^" + [regex]::Escape($Key) + "\s*=.*$"
    $line = $Key + " = " + $Value

    if ([regex]::IsMatch($Text, $pattern)) {
        return [regex]::Replace($Text, $pattern, $line, 1)
    }

    $generalPattern = "(?m)^\[general\]\s*$"

    if (![regex]::IsMatch($Text, $generalPattern)) {
        throw "Generated TOML has no [general] section."
    }

    return [regex]::Replace(
        $Text,
        $generalPattern,
        "[general]" + [Environment]::NewLine + $line,
        1
    )
}

function Ensure-TomlArrayEntries {
    param([string]$Text, [string]$Key, [string[]]$Entries)

    $pattern = "(?ms)(^" + [regex]::Escape($Key) + "\s*=\s*\[\s*\r?\n)(.*?)(^\s*\])"
    $match = [regex]::Match($Text, $pattern)

    if (!$match.Success) {
        throw "Generated TOML has no '$Key = [...]' array."
    }

    $body = $match.Groups[2].Value

    foreach ($entry in $Entries) {
        $quoted = '"' + $entry + '"'

        if ($body -notmatch [regex]::Escape($quoted)) {
            $body += "  " + $quoted + "," + [Environment]::NewLine
        }
    }

    return $Text.Substring(0, $match.Index) +
           $match.Groups[1].Value +
           $body +
           $match.Groups[3].Value +
           $Text.Substring($match.Index + $match.Length)
}

function Find-BuiltTool {
    param([string]$Name)

    $hit = Get-ChildItem -LiteralPath $BuildRoot -Filter $Name -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (!$hit) {
        throw "Built tool '$Name' was not found under $BuildRoot."
    }

    return $hit.FullName
}

try {
    $Git = Require-Command "git"
    $CMake = Require-Command "cmake"
    Require-MsvcToolchain

    Remove-Item Env:CMAKE_GENERATOR -ErrorAction SilentlyContinue
    Remove-Item Env:CMAKE_GENERATOR_PLATFORM -ErrorAction SilentlyContinue
    Remove-Item Env:CMAKE_GENERATOR_TOOLSET -ErrorAction SilentlyContinue

    $GameRoot = Resolve-GameRoot $GameRoot
    $Elf = Join-Path $GameRoot "SCUS_971.77"
    $DistDir = Join-Path $GameRoot "DownhillRecompiled"

    Validate-Elf $Elf

    Write-Host "[2/7] Preparing pinned PS2Recomp checkout..." -ForegroundColor Cyan

    if (!(Test-Path -LiteralPath (Join-Path $Ps2RecompRoot ".git"))) {
        Invoke-Native $Git "clone" "https://github.com/ran-j/PS2Recomp.git" $Ps2RecompRoot
    }

    Invoke-Native $Git "-C" $Ps2RecompRoot "fetch" "origin" $PinnedPs2Recomp "--depth=1"
    Invoke-Native $Git "-C" $Ps2RecompRoot "reset" "--hard" $PinnedPs2Recomp

    $RunnerDir = Join-Path $Ps2RecompRoot "ps2xRuntime\src\runner"
    $RuntimeInclude = Join-Path $Ps2RecompRoot "ps2xRuntime\include"

    Get-ChildItem -LiteralPath $RunnerDir -Filter "*.cpp" -File -ErrorAction SilentlyContinue |
        Remove-Item -Force

    $oldFunctionHeader = Join-Path $RuntimeInclude "ps2_recompiled_functions.h"
    $oldStubHeader = Join-Path $RuntimeInclude "ps2_recompiled_stubs.h"
    Remove-Item -Force -ErrorAction SilentlyContinue $oldFunctionHeader
    Remove-Item -Force -ErrorAction SilentlyContinue $oldStubHeader

    Write-Host "[3/7] Building ps2_analyzer and ps2_recomp..." -ForegroundColor Cyan

    $configureToolsArgs = @(
        "-S", $Ps2RecompRoot,
        "-B", $BuildRoot,
        "-A", "x64",
        "-DPS2X_BUILD_RUNTIME=OFF",
        "-DPS2X_BUILD_RECOMP=ON",
        "-DPS2X_BUILD_ANALYZER=ON",
        "-DPS2X_BUILD_TEST=OFF",
        "-DPS2X_BUILD_STUDIO=OFF"
    )
    Invoke-Native $CMake @configureToolsArgs

    $buildToolsArgs = @(
        "--build", $BuildRoot,
        "--config", "Release",
        "--target", "ps2_recomp", "ps2_analyzer",
        "--parallel"
    )
    Invoke-Native $CMake @buildToolsArgs

    $AnalyzerExe = Find-BuiltTool "ps2_analyzer.exe"
    $RecompExe = Find-BuiltTool "ps2_recomp.exe"

    Write-Host "[4/7] Analyzing the retail ELF and preparing Downhill TOML..." -ForegroundColor Cyan
    Invoke-Native $AnalyzerExe $Elf $AutoConfig

    $toml = Get-Content -Raw -LiteralPath $AutoConfig
    $elfToml = $Elf.Replace("\", "/")
    $runnerToml = $RunnerDir.Replace("\", "/")
    $ghidraToml = ""

    if (Test-Path -LiteralPath $GhidraCsv) {
        $ghidraToml = $GhidraCsv.Replace("\", "/")
        Write-Host "      Ghidra function map found and enabled." -ForegroundColor Green
    }
    else {
        Write-Host "      No Ghidra CSV yet; using analyzer discovery for this pass." -ForegroundColor Yellow
    }

    $toml = Set-TomlScalar $toml "input" ('"' + $elfToml + '"')
    $toml = Set-TomlScalar $toml "output" ('"' + $runnerToml + '"')
    $toml = Set-TomlScalar $toml "ghidra_output" ('"' + $ghidraToml + '"')
    $toml = Set-TomlScalar $toml "single_file_output" "true"
    $toml = Set-TomlScalar $toml "low_memory_mode" "true"
    $toml = Set-TomlScalar $toml "output_worker_threads" "1"

    $toml = Ensure-TomlArrayEntries $toml "stubs" @(
        "scePadRead@0x00254050",
        "sceSifSendCmd@0x0025C440"
    )

    $toml = Ensure-TomlArrayEntries $toml "entry_points" @(
        "0x0010A008",
        "0x001FB6C0",
        "0x00254050",
        "0x0025C440"
    )

    [IO.File]::WriteAllText($AutoConfig, $toml, (New-Object System.Text.UTF8Encoding($false)))

    Write-Host "[5/7] Generating recompiled C++..." -ForegroundColor Cyan
    Invoke-Native $RecompExe $AutoConfig

    $GeneratedFunctionsHeader = Join-Path $RunnerDir "ps2_recompiled_functions.h"
    $GeneratedStubsHeader = Join-Path $RunnerDir "ps2_recompiled_stubs.h"
    $GeneratedRegistration = Join-Path $RunnerDir "register_functions.cpp"
    $GeneratedFunctionsCpp = Join-Path $RunnerDir "ps2_recompiled_functions.cpp"

    foreach ($required in @(
        $GeneratedFunctionsHeader,
        $GeneratedStubsHeader,
        $GeneratedRegistration,
        $GeneratedFunctionsCpp
    )) {
        if (!(Test-Path -LiteralPath $required)) {
            throw "Recompiler did not generate required file: $required"
        }
    }

    Copy-Item -Force $GeneratedFunctionsHeader (Join-Path $RuntimeInclude "ps2_recompiled_functions.h")
    Copy-Item -Force $GeneratedStubsHeader (Join-Path $RuntimeInclude "ps2_recompiled_stubs.h")
    Copy-Item -Force $OverrideSource (Join-Path $RunnerDir "downhill_domination_overrides.cpp")

    Write-Host "[6/7] Building native Windows x64 runner..." -ForegroundColor Cyan

    $configureRuntimeArgs = @(
        "-S", $Ps2RecompRoot,
        "-B", $BuildRoot,
        "-A", "x64",
        "-DPS2X_BUILD_RUNTIME=ON",
        "-DPS2X_BUILD_RECOMP=ON",
        "-DPS2X_BUILD_ANALYZER=ON",
        "-DPS2X_BUILD_TEST=OFF",
        "-DPS2X_BUILD_STUDIO=OFF",
        "-DPS2X_ENABLE_FFMPEG=OFF",
        "-DPS2X_ENABLE_DEBUG_UI=OFF",
        "-DPS2X_ENABLE_RUNTIME_LOGS=ON",
        "-DPS2X_ENABLE_AGRESSIVE_LOGS=ON",
        "-DPS2X_ENABLE_IOP_RPC_TRACE=ON",
        "-DPS2X_SHOW_WINDOWS_CONSOLE=ON",
        ("-DPS2X_DEFAULT_BOOT_ELF=" + $Elf)
    )
    Invoke-Native $CMake @configureRuntimeArgs

    $buildRuntimeArgs = @(
        "--build", $BuildRoot,
        "--config", "Release",
        "--target", "ps2EntryRunner",
        "--parallel"
    )
    Invoke-Native $CMake @buildRuntimeArgs

    $Runner = Get-ChildItem -LiteralPath $BuildRoot -Filter "ps2EntryRunner.exe" -File -Recurse |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (!$Runner) {
        throw "ps2EntryRunner.exe was not found after a successful build."
    }

    Write-Host "[7/7] Staging DownhillRecompiled..." -ForegroundColor Cyan

    New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
    Copy-Item -Force $Runner.FullName (Join-Path $DistDir "ps2EntryRunner.exe")

    Get-ChildItem -LiteralPath $Runner.Directory.FullName -Filter "*.dll" -File -ErrorAction SilentlyContinue |
        ForEach-Object {
            Copy-Item -Force $_.FullName $DistDir
        }

    $runCmdLines = @(
        "@echo off",
        "cd /d ""%~dp0""",
        """%~dp0ps2EntryRunner.exe"" ""$Elf""",
        "echo.",
        "echo Exit code: %ERRORLEVEL%",
        "pause"
    )
    $runCmd = $runCmdLines -join [Environment]::NewLine
    Set-Content -LiteralPath (Join-Path $DistDir "RUN_DOWNHILL.cmd") -Value $runCmd -Encoding ASCII

    $summary = [ordered]@{
        result = "build-complete"
        ps2recomp_commit = $PinnedPs2Recomp
        game_root = $GameRoot
        elf = $Elf
        config = $AutoConfig
        ghidra_map_used = (Test-Path -LiteralPath $GhidraCsv)
        runner = (Join-Path $DistDir "ps2EntryRunner.exe")
        run_script = (Join-Path $DistDir "RUN_DOWNHILL.cmd")
        transcript = $Transcript
    }

    $summary |
        ConvertTo-Json -Depth 4 |
        Set-Content -LiteralPath (Join-Path $LocalAnalysisDir "last_build.json") -Encoding UTF8

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host " Native compiler/bootstrap completed." -ForegroundColor Green
    Write-Host " Runner: $($summary.runner)" -ForegroundColor Green
    Write-Host " Run:    $($summary.run_script)" -ForegroundColor Green
    Write-Host " Log:    $Transcript" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "BUILD FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Transcript: $Transcript" -ForegroundColor Yellow
    exit 1
}
finally {
    try {
        Stop-Transcript | Out-Null
    }
    catch {
    }
}
