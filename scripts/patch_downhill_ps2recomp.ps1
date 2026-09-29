param(
    [Parameter(Mandatory=$true)][string]$Ps2RecompRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root=(Resolve-Path -LiteralPath $Ps2RecompRoot).Path
$path=Join-Path $root 'ps2xRuntime\src\lib\ps2_memory.cpp'
if(!(Test-Path -LiteralPath $path)){throw "PS2Recomp ps2_memory.cpp not found: $path"}

$text=Get-Content -Raw -LiteralPath $path
$old=@'
        case 0x10003C10u:     // VIF1_FBRST
            if (value & 0x1u) // RST
            {
                const bool wasPath3Masked = m_path3Masked;
                std::memset(&vif1_regs, 0, sizeof(vif1_regs));
                m_vif1PendingPath2ImageQwc = 0u;
'@
$new=@'
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

if($text.Contains($new)){
    Write-Host 'Downhill VIF1 ROW/COL preservation patch is already applied.'
    exit 0
}
if(!$text.Contains($old)){
    throw 'Pinned PS2Recomp VIF1_FBRST block no longer matches the expected source. Refusing to patch blindly.'
}

$patched=$text.Replace($old,$new)
[IO.File]::WriteAllText($path,$patched,(New-Object Text.UTF8Encoding($false)))

$verify=Get-Content -Raw -LiteralPath $path
if($verify -notmatch 'savedRow\[4\]' -or $verify -notmatch 'savedCol\[4\]'){
    throw 'VIF1 ROW/COL preservation patch verification failed.'
}

Write-Host 'Applied Downhill VIF1 ROW/COL preservation patch.' -ForegroundColor Green
