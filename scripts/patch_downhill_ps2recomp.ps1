param(
    [Parameter(Mandatory=$true)][string]$Ps2RecompRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path -LiteralPath $Ps2RecompRoot).Path
$memoryPath = Join-Path $root 'ps2xRuntime\src\lib\ps2_memory.cpp'
$testPath = Join-Path $root 'ps2xTest\src\ps2_memory_tests.cpp'

foreach($path in @($memoryPath,$testPath)){
    if(!(Test-Path -LiteralPath $path)){throw "Required pinned PS2Recomp source not found: $path"}
}

$memoryText = Get-Content -Raw -LiteralPath $memoryPath
$vif0Old = @'
    if (address >= 0x10003800u && address < 0x10003A00u)
    {
        m_vifWriteCount.fetch_add(1, std::memory_order_relaxed);
        return true;
    }
'@

$vif0New = @'
    if (address >= 0x10003800u && address < 0x10003A00u)
    {
        m_vifWriteCount.fetch_add(1, std::memory_order_relaxed);

        if (address == 0x10003810u) // VIF0_FBRST
        {
            if (value & 0x1u) // RST
            {
                // VIF FBRST.RST preserves ROW/COL. Downhill Domination is a
                // known title which depends on this behavior for both VIFs.
                uint32_t savedRow[4]{};
                uint32_t savedCol[4]{};
                std::memcpy(savedRow, vif0_regs.row, sizeof(savedRow));
                std::memcpy(savedCol, vif0_regs.col, sizeof(savedCol));

                std::memset(&vif0_regs, 0, sizeof(vif0_regs));
                std::memcpy(vif0_regs.row, savedRow, sizeof(savedRow));
                std::memcpy(vif0_regs.col, savedCol, sizeof(savedCol));
            }

            if (value & 0x8u) // STC
            {
                vif0_regs.stat &= ~((1u << 8) | (1u << 9) | (1u << 10) |
                                    (1u << 11) | (1u << 12) | (1u << 13));
            }
        }

        return true;
    }
'@

if(!$memoryText.Contains($vif0New)){
    if(!$memoryText.Contains($vif0Old)){
        throw 'Pinned PS2Recomp VIF0 register-write block no longer matches expected source. Refusing to patch blindly.'
    }
    $memoryText = $memoryText.Replace($vif0Old,$vif0New)
}

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
}
[IO.File]::WriteAllText($memoryPath,$memoryText,(New-Object Text.UTF8Encoding($false)))

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

if(!$testText.Contains('VIF0 RST should preserve ROW[0]')){
    $vif0Anchor = @'
        tc.Run("VIF double-buffer OFFSET BASE and MSCAL update TOPS and ITOPS", [](TestCase &t)
'@
    $vif0Tests = @'
        tc.Run("VIF0 FBRST RST clears command state and preserves ROW COL", [](TestCase &t)
        {
            PS2Memory mem;
            t.IsTrue(mem.initialize(), "PS2Memory initialize should succeed");

            mem.vif0_regs.mark = 0x1357u;
            mem.vif0_regs.cycle = 0x0203u;
            mem.vif0_regs.mode = 1u;
            mem.vif0_regs.num = 9u;
            mem.vif0_regs.mask = 0x76543210u;
            mem.vif0_regs.code = 0xDEADBEEFu;
            mem.vif0_regs.stat = 0x3F00u;
            mem.vif0_regs.row[0] = 0x10101010u;
            mem.vif0_regs.row[1] = 0x20202020u;
            mem.vif0_regs.row[2] = 0x30303030u;
            mem.vif0_regs.row[3] = 0x40404040u;
            mem.vif0_regs.col[0] = 0xB0B0B001u;
            mem.vif0_regs.col[1] = 0xB0B0B002u;
            mem.vif0_regs.col[2] = 0xB0B0B003u;
            mem.vif0_regs.col[3] = 0xB0B0B004u;

            t.IsTrue(mem.writeIORegister(0x10003810u, 0x1u), "VIF0 FBRST RST write should succeed");

            t.Equals(mem.vif0_regs.mark, 0u, "VIF0 RST should clear MARK");
            t.Equals(mem.vif0_regs.cycle, 0u, "VIF0 RST should clear CYCLE");
            t.Equals(mem.vif0_regs.mode, 0u, "VIF0 RST should clear MODE");
            t.Equals(mem.vif0_regs.num, 0u, "VIF0 RST should clear NUM");
            t.Equals(mem.vif0_regs.mask, 0u, "VIF0 RST should clear MASK");
            t.Equals(mem.vif0_regs.code, 0u, "VIF0 RST should clear CODE");
            t.Equals(mem.vif0_regs.stat, 0u, "VIF0 RST should clear STAT");
            t.Equals(mem.vif0_regs.row[0], 0x10101010u, "VIF0 RST should preserve ROW[0]");
            t.Equals(mem.vif0_regs.row[3], 0x40404040u, "VIF0 RST should preserve ROW[3]");
            t.Equals(mem.vif0_regs.col[0], 0xB0B0B001u, "VIF0 RST should preserve COL[0]");
            t.Equals(mem.vif0_regs.col[3], 0xB0B0B004u, "VIF0 RST should preserve COL[3]");
        });

        tc.Run("VIF0 FBRST STC clears stall and interrupt status bits", [](TestCase &t)
        {
            PS2Memory mem;
            t.IsTrue(mem.initialize(), "PS2Memory initialize should succeed");

            mem.vif0_regs.stat = 0x3F00u | 0x55u;
            t.IsTrue(mem.writeIORegister(0x10003810u, 0x8u), "VIF0 FBRST STC write should succeed");
            t.Equals(mem.vif0_regs.stat, 0x55u, "VIF0 STC should clear status bits 8..13 only");
        });

        tc.Run("VIF double-buffer OFFSET BASE and MSCAL update TOPS and ITOPS", [](TestCase &t)
'@
    if(!$testText.Contains($vif0Anchor)){
        throw 'Pinned PS2Recomp VIF test insertion point no longer matches expected source. Refusing to patch blindly.'
    }
    $testText = $testText.Replace($vif0Anchor,$vif0Tests)
    [IO.File]::WriteAllText($testPath,$testText,(New-Object Text.UTF8Encoding($false)))
}

$verifyMemory = Get-Content -Raw -LiteralPath $memoryPath
$verifyTest = Get-Content -Raw -LiteralPath $testPath
if($verifyMemory -notmatch 'savedRow\[4\]' -or
   $verifyMemory -notmatch 'savedCol\[4\]' -or
   $verifyMemory -notmatch '0x10003810u' -or
   $verifyTest -notmatch 'RST should preserve ROW\[0\]' -or
   $verifyTest -notmatch 'RST should preserve COL\[3\]' -or
   $verifyTest -notmatch 'VIF0 RST should preserve ROW\[0\]' -or
   $verifyTest -notmatch 'VIF0 STC should clear status bits 8\.\.13 only'){
    throw 'Downhill VIF0/VIF1 compatibility patch verification failed.'
}

Write-Host 'Applied and verified Downhill VIF0/VIF1 FBRST compatibility patches + regression tests.' -ForegroundColor Green
