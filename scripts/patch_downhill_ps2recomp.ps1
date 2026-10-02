param(
    [Parameter(Mandatory=$true)][string]$Ps2RecompRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path -LiteralPath $Ps2RecompRoot).Path
$runtimePin = (& git -C $root rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $runtimePin -ne '75d729ce40d7eed9649fd4bb05628dee520f3d0c') {
    throw 'Pinned PS2Recomp revision required for runtime bring-up patches.'
}
$memoryPath = Join-Path $root 'ps2xRuntime\src\lib\ps2_memory.cpp'
$testPath = Join-Path $root 'ps2xTest\src\ps2_memory_tests.cpp'
$fileIoPath = Join-Path $root 'ps2xRuntime\src\lib\Kernel\Syscalls\FileIO.cpp'

foreach($path in @($memoryPath,$testPath,$fileIoPath)){
    if(!(Test-Path -LiteralPath $path)){throw "Required pinned PS2Recomp source not found: $path"}
}

$memoryText = Get-Content -Raw -LiteralPath $memoryPath
$memoryOld = @'
        case 0x10003C10u:     // VIF1_FBRST
            if (value & 0x1u) // RST
            {
                const bool wasPath3Masked = m_path3Masked;
                std::memset(&vif1_regs, 0, sizeof(vif1_regs));
                m_vif1PendingPath2ImageQwc = 0u;
'@
$memoryNew = @'
        case 0x10003C10u:     // VIF1_FBRST
            if (value & 0x1u) // RST
            {
                const bool wasPath3Masked = m_path3Masked;

                // VIF FBRST.RST does not discard the ROW/COL data registers.
                // Downhill Domination relies on these values surviving a VIF1 reset.
                uint32_t savedRow[4]{};
                uint32_t savedCol[4]{};
                std::memcpy(savedRow, vif1_regs.row, sizeof(savedRow));
                std::memcpy(savedCol, vif1_regs.col, sizeof(savedCol));

                std::memset(&vif1_regs, 0, sizeof(vif1_regs));
                std::memcpy(vif1_regs.row, savedRow, sizeof(savedRow));
                std::memcpy(vif1_regs.col, savedCol, sizeof(savedCol));
                m_vif1PendingPath2ImageQwc = 0u;
'@

if(!$memoryText.Contains($memoryNew)){
    if(!$memoryText.Contains($memoryOld)){
        throw 'Pinned PS2Recomp VIF1_FBRST block no longer matches expected source. Refusing to patch blindly.'
    }
    $memoryText = $memoryText.Replace($memoryOld,$memoryNew)
    [IO.File]::WriteAllText($memoryPath,$memoryText,(New-Object Text.UTF8Encoding($false)))
}

$testText = Get-Content -Raw -LiteralPath $testPath
$setupOld = @'
            mem.vif1_regs.code = 0xCAFEBABEu;
            mem.vif1_regs.stat = 0x3F00u;

            t.IsTrue(mem.writeIORegister(0x10003C10u, 0x1u), "FBRST RST write should succeed");
'@
$setupNew = @'
            mem.vif1_regs.code = 0xCAFEBABEu;
            mem.vif1_regs.stat = 0x3F00u;
            mem.vif1_regs.row[0] = 0x11111111u;
            mem.vif1_regs.row[1] = 0x22222222u;
            mem.vif1_regs.row[2] = 0x33333333u;
            mem.vif1_regs.row[3] = 0x44444444u;
            mem.vif1_regs.col[0] = 0xAAAAAAA1u;
            mem.vif1_regs.col[1] = 0xAAAAAAA2u;
            mem.vif1_regs.col[2] = 0xAAAAAAA3u;
            mem.vif1_regs.col[3] = 0xAAAAAAA4u;

            t.IsTrue(mem.writeIORegister(0x10003C10u, 0x1u), "FBRST RST write should succeed");
'@

$assertOld = @'
            t.Equals(mem.vif1_regs.stat, 0u, "RST should clear STAT");
        });
'@
$assertNew = @'
            t.Equals(mem.vif1_regs.stat, 0u, "RST should clear STAT");
            t.Equals(mem.vif1_regs.row[0], 0x11111111u, "RST should preserve ROW[0]");
            t.Equals(mem.vif1_regs.row[1], 0x22222222u, "RST should preserve ROW[1]");
            t.Equals(mem.vif1_regs.row[2], 0x33333333u, "RST should preserve ROW[2]");
            t.Equals(mem.vif1_regs.row[3], 0x44444444u, "RST should preserve ROW[3]");
            t.Equals(mem.vif1_regs.col[0], 0xAAAAAAA1u, "RST should preserve COL[0]");
            t.Equals(mem.vif1_regs.col[1], 0xAAAAAAA2u, "RST should preserve COL[1]");
            t.Equals(mem.vif1_regs.col[2], 0xAAAAAAA3u, "RST should preserve COL[2]");
            t.Equals(mem.vif1_regs.col[3], 0xAAAAAAA4u, "RST should preserve COL[3]");
        });
'@

if(!$testText.Contains('RST should preserve ROW[0]')){
    if(!$testText.Contains($setupOld) -or !$testText.Contains($assertOld)){
        throw 'Pinned PS2Recomp VIF FBRST unit test no longer matches expected source. Refusing to patch blindly.'
    }
    $testText = $testText.Replace($setupOld,$setupNew)
    $testText = $testText.Replace($assertOld,$assertNew)
    [IO.File]::WriteAllText($testPath,$testText,(New-Object Text.UTF8Encoding($false)))
}

$fileIoText = Get-Content -Raw -LiteralPath $fileIoPath
$fileIoOld = @'
        const int32_t descriptor = runtime->vfs().open(ps2Path, static_cast<uint32_t>(flags), currentVfsMounts(), runtime->romDevice());
        setReturnS32(ctx, descriptor);
'@
$fileIoNew = @'
        const int32_t descriptor = runtime->vfs().open(ps2Path, static_cast<uint32_t>(flags), currentVfsMounts(), runtime->romDevice());
        if (descriptor < 0)
        {
            std::cerr << "[FileIO:open-failed] guest='" << ps2Path
                      << "' flags=0x" << std::hex << static_cast<uint32_t>(flags)
                      << " pc=0x" << static_cast<uint32_t>(ctx->pc)
                      << std::dec << std::endl;
        }
        setReturnS32(ctx, descriptor);
'@

if(!$fileIoText.Contains($fileIoNew)){
    if(!$fileIoText.Contains($fileIoOld)){
        throw 'Pinned PS2Recomp fioOpen block no longer matches expected source. Refusing to patch blindly.'
    }
    $fileIoText = $fileIoText.Replace($fileIoOld,$fileIoNew)
    [IO.File]::WriteAllText($fileIoPath,$fileIoText,(New-Object Text.UTF8Encoding($false)))
}

$verifyMemory = Get-Content -Raw -LiteralPath $memoryPath
$verifyTest = Get-Content -Raw -LiteralPath $testPath
$verifyFileIo = Get-Content -Raw -LiteralPath $fileIoPath
if($verifyMemory -notmatch 'savedRow\[4\]' -or
   $verifyMemory -notmatch 'savedCol\[4\]' -or
   $verifyTest -notmatch 'RST should preserve ROW\[0\]' -or
   $verifyTest -notmatch 'RST should preserve COL\[3\]' -or
   $verifyFileIo -notmatch '\[FileIO:open-failed\]'){
    throw 'Downhill VIF1 compatibility patch verification failed.'
}

Write-Host 'Applied and verified Downhill VIF1 ROW/COL patch, regression test, and FileIO failure trace.' -ForegroundColor Green

# A reverse check normally fails for a patch that has not been applied yet.
# Windows PowerShell 5 treats native stderr as an error even with 2>$null.
function Test-RuntimePatchApplied([string]$PatchFile) {
    $savedPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'SilentlyContinue'
        & git -C $root apply --reverse --check $PatchFile 2>$null
        $checkExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedPreference
    }
    return ($checkExitCode -eq 0)
}

# Host transfer memory, physical ISO extents, and terminal PSS markers.
# Unwind overlapping diagnostic additions before verifying earlier patches.
foreach ($name in @('vu-xgkick-error-trace', 'gif-image2', 'guest-checkpoint-return', 'guest-missing-target-trace', 'gs-sdk-clear', 'vif-v45-color', 'gs-clear-depth-trace', 'gs-triangle-trace', 'gs-palette-upload-trace', 'gs-clut-entry1-trace', 'gs-vram-watch')) {
    $patchFile = Join-Path (Split-Path -Parent $PSScriptRoot) ("patches/ps2recomp-" + $name + ".patch")
    if (Test-RuntimePatchApplied $patchFile) {
        & git -C $root apply --reverse $patchFile
        if ($LASTEXITCODE -ne 0) { throw "Failed to unwind diagnostic patch: $name" }
    }
}
foreach ($name in @('gs-host-transfer', 'cdvd-iso-extents', 'mpeg-program-end', 'ready-queue-snapshot', 'boot-performance-trace', 'dmac-interrupt-trace', 'cop0-dmac-condition', 'vif1-command-trace', 'gs-pipeline-trace', 'auto-intro-skip', 'gs-texture-trace', 'intro-stream-window', 'gs-clut-reload', 'gs-upload24-continuation', 'gs-clut-trace', 'gs-vram-watch', 'gs-clut-entry1-trace', 'gs-palette-upload-trace', 'gs-image-block-address', 'gs-triangle-trace', 'gs-clear-depth-trace', 'vif-v45-color', 'gs-sdk-clear', 'guest-missing-target-trace', 'guest-checkpoint-return', 'gif-image2', 'vu-xgkick-error-trace')) {
    $patchFile = Join-Path (Split-Path -Parent $PSScriptRoot) ("patches/ps2recomp-" + $name + ".patch")
    if (Test-RuntimePatchApplied $patchFile) { continue }
    & git -C $root apply --check $patchFile
    if ($LASTEXITCODE -ne 0) { throw "Runtime patch does not match pinned source: $name" }
    & git -C $root apply $patchFile
    if ($LASTEXITCODE -ne 0) { throw "Runtime patch failed: $name" }
}
Write-Host 'Applied and verified version-pinned GS, ISO lookup, and MPEG program-end patches.' -ForegroundColor Green
