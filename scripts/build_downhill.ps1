param(
    [string]$GameRoot = "",
    [switch]$MultiFileOutput
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
$ExtraEntryPointsFile = Join-Path $ConfigDir "downhill.extra_entry_points.local.txt"
$GhidraCsv = Join-Path $AnalysisDir "SCUS_971.77.functions.csv"
$GhidraToml = Join-Path $AnalysisDir "SCUS_971.77.ghidra.toml"
$OverrideSource = Join-Path $RepoRoot "src\downhill_domination_overrides.cpp"
$DeepElfAnalyzer = Join-Path $RepoRoot "scripts\analyze_downhill_elf_deep.ps1"
$DeepElfReport = Join-Path $LocalAnalysisDir "SCUS_971.77.deep.json"
$LoggedRunnerSource = Join-Path $RepoRoot "scripts\run_downhill_logged.ps1"
$ProbeRunnerSource = Join-Path $RepoRoot "scripts\run_downhill_probe.ps1"
$TriageSource = Join-Path $RepoRoot "scripts\triage_first_boot.ps1"
$StaticAnalysisSource = Join-Path $RepoRoot "scripts\analyze_recompiled_output.ps1"
$SuggestionSource = Join-Path $RepoRoot "scripts\suggest_bringup_fixes.ps1"
$StubAuditSource = Join-Path $RepoRoot "scripts\audit_runtime_stubs.ps1"
$RuntimePatchSource = Join-Path $RepoRoot "scripts\patch_downhill_ps2recomp.ps1"

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

function Get-TextSha256 {
    param([string]$Text)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        [byte[]]$bytes = (New-Object Text.UTF8Encoding($false)).GetBytes($Text)
        [byte[]]$hash = $sha.ComputeHash($bytes)
        return ([BitConverter]::ToString($hash)).Replace("-", "")
    }
    finally {
        $sha.Dispose()
    }
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

function Detect-GameData {
    param([string]$Root)

    $systemCnf = ""
    $isoPath = ""
    $source = "none"

    $rootSidecar = Join-Path $Root "downhill_cd_root.txt"
    if (Test-Path -LiteralPath $rootSidecar) {
        $sidecarValue = (Get-Content -LiteralPath $rootSidecar -TotalCount 1).Trim()
        if ($sidecarValue -and (Test-Path -LiteralPath $sidecarValue -PathType Container)) {
            $candidate = Join-Path $sidecarValue "SYSTEM.CNF"
            if (Test-Path -LiteralPath $candidate) {
                $systemCnf = $candidate
                $source = "cd-root-sidecar"
            }
        }
    }

    $imageSidecar = Join-Path $Root "downhill_cd_image.txt"
    if (Test-Path -LiteralPath $imageSidecar) {
        $sidecarValue = (Get-Content -LiteralPath $imageSidecar -TotalCount 1).Trim()
        if ($sidecarValue -and (Test-Path -LiteralPath $sidecarValue -PathType Leaf)) {
            $isoPath = [IO.Path]::GetFullPath($sidecarValue)
            $source = if ($source -eq "none") { "cd-image-sidecar" } else { $source + "+cd-image-sidecar" }
        }
    }

    if (!$systemCnf) {
        $directSystemCnf = Join-Path $Root "SYSTEM.CNF"
        if (Test-Path -LiteralPath $directSystemCnf) {
            $systemCnf = $directSystemCnf
            $source = "direct-system-cnf"
        }
        else {
            foreach ($dir in @(Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue)) {
                $candidate = Join-Path $dir.FullName "SYSTEM.CNF"
                if (Test-Path -LiteralPath $candidate) {
                    $systemCnf = $candidate
                    $source = "child-system-cnf"
                    break
                }
            }
        }
    }

    if (!$isoPath) {
        $iso = Get-ChildItem -LiteralPath $Root -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -ieq ".iso" } |
            Sort-Object Length -Descending |
            Select-Object -First 1
        if ($iso) {
            $isoPath = $iso.FullName
            $source = if ($source -eq "none") { "direct-iso" } else { $source + "+direct-iso" }
        }
    }

    $archive = Get-ChildItem -LiteralPath $Root -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '(?i)\.part0*1\.rar$' } |
        Sort-Object Name |
        Select-Object -First 1

    $mode = "elf-only"
    if ($systemCnf -and $isoPath) { $mode = "extracted-disc+iso" }
    elseif ($systemCnf) { $mode = "extracted-disc" }
    elseif ($isoPath) { $mode = "iso" }
    elseif ($archive) { $mode = "multipart-rar" }

    return [pscustomobject][ordered]@{
        mode = $mode
        source = $source
        system_cnf = $systemCnf
        cd_root = if ($systemCnf) { Split-Path $systemCnf -Parent } else { "" }
        iso = $isoPath
        multipart_archive = if ($archive) { $archive.FullName } else { "" }
        prepare_command = if ($archive -and !$systemCnf -and !$isoPath) {
            (Join-Path $RepoRoot "PREPARE_GAME_DATA.cmd")
        } else { "" }
    }
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
        crc32_ieee_u32 = [uint32]$crc32
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
    return [pscustomobject]$identity
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

function Get-TomlArrayEntries {
    param([string]$Text, [string]$Key)

    $pattern = "(?ms)^" + [regex]::Escape($Key) + "\s*=\s*\[(.*?)^\s*\]"
    $match = [regex]::Match($Text, $pattern)
    if (!$match.Success) {
        return @()
    }

    $entries = New-Object System.Collections.Generic.List[string]
    foreach ($quoted in [regex]::Matches($match.Groups[1].Value, '"([^"]+)"')) {
        $value = $quoted.Groups[1].Value.Trim()
        if ($value) {
            $entries.Add($value)
        }
    }

    return @($entries)
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
    $GameData = Detect-GameData $GameRoot

    if ($GameData.mode -eq "elf-only") {
        Write-Warning "No SYSTEM.CNF, ISO, or multipart RAR was found beside the ELF. Native compilation can continue, but game file access may block during first boot."
    }
    elseif ($GameData.mode -eq "multipart-rar") {
        Write-Warning ("Multipart game archive found but not prepared: " + $GameData.multipart_archive)
        Write-Warning ("Run PREPARE_GAME_DATA.cmd before first boot: " + $GameData.prepare_command)
    }
    else {
        Write-Host ("      Game data mode: " + $GameData.mode + " (" + $GameData.source + ")") -ForegroundColor DarkGray
    }

    $ElfIdentity = Validate-Elf $Elf

    if (!(Test-Path -LiteralPath $DeepElfAnalyzer)) {
        throw "Missing deep ELF analyzer: $DeepElfAnalyzer"
    }
    Write-Host "      Running deep R5900/COP/VU/MMI census..." -ForegroundColor DarkCyan
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $DeepElfAnalyzer -Elf $Elf -Out $DeepElfReport -FunctionCsv $GhidraCsv
    if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $DeepElfReport)) {
        throw "Deep ELF analysis failed."
    }

    Write-Host "[2/7] Preparing pinned PS2Recomp checkout..." -ForegroundColor Cyan

    if (!(Test-Path -LiteralPath (Join-Path $Ps2RecompRoot ".git"))) {
        Invoke-Native $Git "clone" "https://github.com/ran-j/PS2Recomp.git" $Ps2RecompRoot
    }

    Invoke-Native $Git "-C" $Ps2RecompRoot "fetch" "origin" $PinnedPs2Recomp "--depth=1"
    Invoke-Native $Git "-C" $Ps2RecompRoot "reset" "--hard" $PinnedPs2Recomp

    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $RuntimePatchSource -Ps2RecompRoot $Ps2RecompRoot
    if ($LASTEXITCODE -ne 0) {
        throw "Downhill PS2Recomp runtime patch failed."
    }

    $RuntimePatchSha256 = (Get-FileHash -LiteralPath $RuntimePatchSource -Algorithm SHA256).Hash
    $RuntimePatchDiff = (& $Git -C $Ps2RecompRoot diff -- ps2xRuntime/src/lib/ps2_memory.cpp ps2xTest/src/ps2_memory_tests.cpp) -join [Environment]::NewLine
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to capture patched PS2Recomp diff."
    }
    if (!$RuntimePatchDiff) {
        throw "Expected Downhill runtime patch diff is empty."
    }
    $RuntimePatchDiffSha256 = Get-TextSha256 $RuntimePatchDiff
    [IO.File]::WriteAllText(
        (Join-Path $LocalAnalysisDir "PS2Recomp.downhill.patch.diff"),
        $RuntimePatchDiff + [Environment]::NewLine,
        (New-Object Text.UTF8Encoding($false))
    )

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
    $ghidraTomlPath = ""
    $GhidraImportedStubs = @()
    $GhidraImportedEntryPoints = @()

    if (Test-Path -LiteralPath $GhidraCsv) {
        $ghidraTomlPath = $GhidraCsv.Replace("\", "/")
        Write-Host "      Ghidra function map found and enabled." -ForegroundColor Green

        if (Test-Path -LiteralPath $GhidraToml) {
            $ghidraExport = Get-Content -Raw -LiteralPath $GhidraToml
            $GhidraImportedStubs = @(Get-TomlArrayEntries $ghidraExport "stubs" | Sort-Object -Unique)
            $GhidraImportedEntryPoints = @(Get-TomlArrayEntries $ghidraExport "untracked_stubs" | Sort-Object -Unique)
            Write-Host ("      Ghidra classifications: stubs=" + $GhidraImportedStubs.Count +
                        ", entry hints=" + $GhidraImportedEntryPoints.Count) -ForegroundColor DarkGray
        }
        else {
            Write-Warning "Ghidra CSV exists but SCUS_971.77.ghidra.toml is missing; using Ghidra boundaries without Ghidra stub classifications."
        }
    }
    else {
        Write-Host "      No Ghidra CSV yet; using analyzer discovery for this pass." -ForegroundColor Yellow
    }

    $toml = Set-TomlScalar $toml "input" ('"' + $elfToml + '"')
    $toml = Set-TomlScalar $toml "output" ('"' + $runnerToml + '"')
    $toml = Set-TomlScalar $toml "ghidra_output" ('"' + $ghidraTomlPath + '"')
    $OutputMode = if ($MultiFileOutput) { "multi-file" } else { "single-file" }
    $SingleFileToml = if ($MultiFileOutput) { "false" } else { "true" }
    $toml = Set-TomlScalar $toml "single_file_output" $SingleFileToml
    Write-Host ("      Recompiler output mode: " + $OutputMode) -ForegroundColor DarkGray
    $toml = Set-TomlScalar $toml "low_memory_mode" "true"
    $toml = Set-TomlScalar $toml "output_worker_threads" "1"

    # Conservative first-boot policy. Instruction-class-specific replacements
    # stay disabled until a concrete retail blocker justifies one. Generic
    # analyzer patches remain eligible in PS2Recomp.
    $toml = Set-TomlScalar $toml "patch_syscalls" "false"
    $toml = Set-TomlScalar $toml "patch_cop0" "false"
    $toml = Set-TomlScalar $toml "patch_cache" "false"

    if ($GhidraImportedStubs.Count -gt 0) {
        $toml = Ensure-TomlArrayEntries $toml "stubs" $GhidraImportedStubs
    }
    if ($GhidraImportedEntryPoints.Count -gt 0) {
        $toml = Ensure-TomlArrayEntries $toml "entry_points" $GhidraImportedEntryPoints
    }

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

    $LocalExtraEntries = @()
    if (Test-Path -LiteralPath $ExtraEntryPointsFile) {
        foreach ($line in Get-Content -LiteralPath $ExtraEntryPointsFile) {
            $value = $line.Trim()
            if (!$value -or $value.StartsWith("#")) {
                continue
            }

            if ($value -notmatch '^0x([0-9A-Fa-f]{8})$') {
                throw ("Invalid local entry-point literal in {0}: {1}" -f $ExtraEntryPointsFile, $value)
            }

            [uint32]$pc = [Convert]::ToUInt32($Matches[1], 16)
            if ($pc -lt [uint32]0x0010A000 -or
                $pc -ge [uint32]0x0029DCF0 -or
                (($pc -band 3) -ne 0)) {
                throw ("Local entry point is outside the validated file-backed executable range or is unaligned: {0}" -f $value)
            }

            $LocalExtraEntries += ("0x{0:X8}" -f $pc)
        }

        $LocalExtraEntries = @($LocalExtraEntries | Sort-Object -Unique)
        if ($LocalExtraEntries.Count -gt 0) {
            $toml = Ensure-TomlArrayEntries $toml "entry_points" $LocalExtraEntries
            Write-Host ("      Added local entry-point overrides: " + ($LocalExtraEntries -join ", ")) -ForegroundColor Yellow
        }
    }

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
        $GeneratedRegistration
    )) {
        if (!(Test-Path -LiteralPath $required)) {
            throw "Recompiler did not generate required file: $required"
        }
    }

    if ($MultiFileOutput) {
        $GeneratedCppFiles = @(
            Get-ChildItem -LiteralPath $RunnerDir -Filter "*.cpp" -File |
                Where-Object { $_.Name -ne "register_functions.cpp" } |
                Sort-Object Name
        )
        if ($GeneratedCppFiles.Count -eq 0) {
            throw "Multi-file recompilation produced no function C++ files."
        }
    }
    else {
        if (!(Test-Path -LiteralPath $GeneratedFunctionsCpp)) {
            throw "Recompiler did not generate combined output: $GeneratedFunctionsCpp"
        }
        $GeneratedCppFiles = @((Get-Item -LiteralPath $GeneratedFunctionsCpp))
    }

    $registrationCheck = Get-Content -Raw -LiteralPath $GeneratedRegistration
    foreach ($requiredAddress in @(
        "0x0010A008",
        "0x001FB6C0",
        "0x00254050",
        "0x0025C440"
    )) {
        $hexBody = $requiredAddress.Substring(2).TrimStart([char]'0')
        if (!$hexBody) { $hexBody = "0" }
        if ($registrationCheck -notmatch ("(?i)//\s*0x0*" + [regex]::Escape($hexBody) + "\b")) {
            throw "Generated function table does not contain required guest entry $requiredAddress."
        }
    }

    Write-Host "      Required Downhill entry/binding addresses are present in the generated function table." -ForegroundColor Green

    $StaticAnalysisOut = Join-Path $LocalAnalysisDir "SCUS_971.77.recompiled.json"
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $StaticAnalysisSource `
        -Config $AutoConfig `
        -GeneratedDir $RunnerDir `
        -Out $StaticAnalysisOut
    if ($LASTEXITCODE -ne 0) {
        throw "Static recompilation report failed."
    }

    $StubAuditOut = Join-Path $LocalAnalysisDir "SCUS_971.77.runtime_stubs.json"
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $StubAuditSource `
        -Config $AutoConfig `
        -Ps2RecompRoot $Ps2RecompRoot `
        -Out $StubAuditOut
    if ($LASTEXITCODE -ne 0) {
        throw "Runtime stub audit failed."
    }
    $StubAudit = Get-Content -Raw -LiteralPath $StubAuditOut | ConvertFrom-Json
    if ([int]$StubAudit.todo -gt 0 -or [int]$StubAudit.not_found -gt 0) {
        Write-Warning ("Runtime stub audit found TODO/not-found handlers: TODO=" + $StubAudit.todo + ", missing=" + $StubAudit.not_found)
    }

    Copy-Item -Force $GeneratedFunctionsHeader (Join-Path $RuntimeInclude "ps2_recompiled_functions.h")
    Copy-Item -Force $GeneratedStubsHeader (Join-Path $RuntimeInclude "ps2_recompiled_stubs.h")
    $OverrideTarget = Join-Path $RunnerDir "downhill_domination_overrides.cpp"
    $overrideText = Get-Content -Raw -LiteralPath $OverrideSource
    $crcLiteral = ("0x{0:X8}u" -f [uint32]$ElfIdentity.crc32_ieee_u32)
    $crcPattern = 'constexpr uint32_t kExpectedFileCrc32 = 0x[0-9A-Fa-f]{8}u;'
    if ($overrideText -notmatch $crcPattern) {
        throw "Downhill override CRC placeholder was not found."
    }
    $overrideText = [regex]::Replace(
        $overrideText,
        $crcPattern,
        ("constexpr uint32_t kExpectedFileCrc32 = " + $crcLiteral + ";"),
        1
    )
    [IO.File]::WriteAllText(
        $OverrideTarget,
        $overrideText,
        (New-Object Text.UTF8Encoding($false))
    )
    Write-Host ("      Runtime override locked to CRC32/IEEE " + (Hex32 ([uint32]$ElfIdentity.crc32_ieee_u32))) -ForegroundColor Green

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
        "-DPS2X_STRICT_RETURN_DIAGNOSTICS=ON",
        "-DPS2X_ENABLE_RUNNER_UNITY_BUILD=OFF",
        "-DPS2X_SHOW_WINDOWS_CONSOLE=ON",
        "-DCMAKE_CXX_FLAGS=/bigobj"
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
    $StagedRunner = Join-Path $DistDir "ps2EntryRunner.exe"
    Copy-Item -Force $Runner.FullName $StagedRunner

    Get-ChildItem -LiteralPath $Runner.Directory.FullName -Filter "*.dll" -File -ErrorAction SilentlyContinue |
        ForEach-Object {
            Copy-Item -Force $_.FullName $DistDir
        }

    Copy-Item -Force $LoggedRunnerSource (Join-Path $DistDir "run_downhill_logged.ps1")
    Copy-Item -Force $ProbeRunnerSource (Join-Path $DistDir "run_downhill_probe.ps1")
    Copy-Item -Force $TriageSource (Join-Path $DistDir "triage_first_boot.ps1")
    Copy-Item -Force $StaticAnalysisOut (Join-Path $DistDir "recompiled_report.json")
    Copy-Item -Force $DeepElfReport (Join-Path $DistDir "SCUS_971.77.deep.json")
    Copy-Item -Force $StubAuditOut (Join-Path $DistDir "runtime_stubs_report.json")
    Copy-Item -Force $SuggestionSource (Join-Path $DistDir "suggest_bringup_fixes.ps1")
    Copy-Item -Force $AutoConfig (Join-Path $DistDir "downhill.auto.toml")

    $runCmdLines = @(
        "@echo off",
        "cd /d ""%~dp0""",
        "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File ""%~dp0run_downhill_logged.ps1"" -Elf ""%~dp0..\SCUS_971.77""",
        "echo.",
        "pause"
    )
    $runCmd = $runCmdLines -join [Environment]::NewLine
    Set-Content -LiteralPath (Join-Path $DistDir "RUN_DOWNHILL.cmd") -Value $runCmd -Encoding ASCII

    $probeCmdLines = @(
        "@echo off",
        "cd /d ""%~dp0""",
        "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File ""%~dp0run_downhill_probe.ps1"" -Elf ""%~dp0..\SCUS_971.77"" -TimeoutSeconds 90",
        "echo.",
        "echo Diagnostic probe exit code: %ERRORLEVEL%",
        "pause"
    )
    $probeCmd = $probeCmdLines -join [Environment]::NewLine
    Set-Content -LiteralPath (Join-Path $DistDir "RUN_PROBE_90S.cmd") -Value $probeCmd -Encoding ASCII

    $functionHeaderText = Get-Content -Raw -LiteralPath $GeneratedFunctionsHeader
    $stubHeaderText = Get-Content -Raw -LiteralPath $GeneratedStubsHeader
    $registrationText = Get-Content -Raw -LiteralPath $GeneratedRegistration

    [int64]$GeneratedCppBytes = 0
    [int]$TodoNamedOccurrences = 0
    $GeneratedCppMetrics = New-Object System.Collections.Generic.List[object]
    foreach ($cppFile in $GeneratedCppFiles) {
        $cppText = Get-Content -Raw -LiteralPath $cppFile.FullName
        $TodoNamedOccurrences += ([regex]::Matches($cppText, "TODO_NAMED")).Count
        $GeneratedCppBytes += [int64]$cppFile.Length
        $GeneratedCppMetrics.Add([ordered]@{
            file = $cppFile.Name
            bytes = [int64]$cppFile.Length
            sha256 = (Get-FileHash -LiteralPath $cppFile.FullName -Algorithm SHA256).Hash
        })
    }

    $PrimaryGeneratedCppSha256 = $null
    if ($GeneratedCppFiles.Count -eq 1) {
        $PrimaryGeneratedCppSha256 = (Get-FileHash -LiteralPath $GeneratedCppFiles[0].FullName -Algorithm SHA256).Hash
    }

    $metrics = [ordered]@{
        output_mode = $OutputMode
        generated_cpp_file_count = $GeneratedCppFiles.Count
        generated_function_declarations = ([regex]::Matches($functionHeaderText, "(?m)^void\s+[A-Za-z_][A-Za-z0-9_]*\s*\(")).Count
        generated_stub_declarations = ([regex]::Matches($stubHeaderText, "(?m)^void\s+[A-Za-z_][A-Za-z0-9_]*\s*\(")).Count
        todo_named_occurrences = $TodoNamedOccurrences
        registered_function_slots = ([regex]::Matches($registrationText, "(?m)^\s*g_ps2RecompiledFunctionTable\s*\[")).Count
        generated_cpp_bytes = $GeneratedCppBytes
        generated_cpp_sha256 = $PrimaryGeneratedCppSha256
        generated_cpp_files = $GeneratedCppMetrics
        config_sha256 = (Get-FileHash -LiteralPath $AutoConfig -Algorithm SHA256).Hash
        runner_bytes = (Get-Item -LiteralPath $StagedRunner).Length
        runner_sha256 = (Get-FileHash -LiteralPath $StagedRunner -Algorithm SHA256).Hash
        runtime_override_crc32_ieee = Hex32 ([uint32]$ElfIdentity.crc32_ieee_u32)
    }

    $summary = [ordered]@{
        result = "build-complete"
        ps2recomp_commit = $PinnedPs2Recomp
        runtime_patch_script_sha256 = $RuntimePatchSha256
        runtime_patch_diff_sha256 = $RuntimePatchDiffSha256
        game_root = $GameRoot
        elf = $Elf
        config = $AutoConfig
        ghidra_map_used = (Test-Path -LiteralPath $GhidraCsv)
        ghidra_toml_used = (Test-Path -LiteralPath $GhidraToml)
        ghidra_imported_stubs = $GhidraImportedStubs
        ghidra_imported_entry_points = $GhidraImportedEntryPoints
        patch_policy = [ordered]@{
            patch_syscalls = $false
            patch_cop0 = $false
            patch_cache = $false
        }
        local_extra_entry_points = $LocalExtraEntries
        game_data = $GameData
        runner = $StagedRunner
        run_script = (Join-Path $DistDir "RUN_DOWNHILL.cmd")
        probe_script = (Join-Path $DistDir "RUN_PROBE_90S.cmd")
        first_boot_latest_log = (Join-Path $DistDir "first_boot_latest.log")
        first_boot_triage = (Join-Path $DistDir "first_boot_triage.json")
        recompiled_report = (Join-Path $DistDir "recompiled_report.json")
        deep_elf_report = (Join-Path $DistDir "SCUS_971.77.deep.json")
        runtime_stubs_report = (Join-Path $DistDir "runtime_stubs_report.json")
        staged_config = (Join-Path $DistDir "downhill.auto.toml")
        bringup_suggestions = (Join-Path $DistDir "first_boot_suggestions.json")
        transcript = $Transcript
        metrics = $metrics
    }

    $summaryJson = $summary | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText(
        (Join-Path $LocalAnalysisDir "last_build.json"),
        $summaryJson,
        (New-Object Text.UTF8Encoding($false))
    )
    [IO.File]::WriteAllText(
        (Join-Path $DistDir "build_report.json"),
        $summaryJson,
        (New-Object Text.UTF8Encoding($false))
    )

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host " Native compiler/bootstrap completed." -ForegroundColor Green
    Write-Host " Runner: $($summary.runner)" -ForegroundColor Green
    Write-Host " Run:    $($summary.run_script)" -ForegroundColor Green
    Write-Host " Build report: $(Join-Path $DistDir "build_report.json")" -ForegroundColor Green
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
