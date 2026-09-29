# Downhill Domination VIF1 compatibility note

## Problem

The pinned PS2Recomp runtime handled a write of VIF1_FBRST.RST (0x10003C10 bit 0) by zeroing the complete VIF1 register structure. That also erased the four ROW and four COL values used by VIF UNPACK.

For Downhill Domination this behavior is not compatible with established PS2 emulation behavior.

## Reference behavior

Current PCSX2 preserves the VIF ROW/COL state across FBRST reset for both VIF0 and VIF1. Its VIF1 reset path contains the historical comment:

    Must Preserve Row/Col registers! (Downhill Domination for testing)

Reference:

https://github.com/PCSX2/pcsx2/blob/master/pcsx2/Vif.cpp

PS2 hardware documentation identifies:

- VIF1_FBRST at 0x10003C10
- ROW registers at 0x10003D00..0x10003D30
- COL registers at 0x10003D40..0x10003D70

Reference:

https://psi-rockin.github.io/ps2tek/

## Local compatibility patch

`scripts/patch_downhill_ps2recomp.ps1` patches the pinned PS2Recomp source so VIF1_FBRST.RST:

1. saves ROW[0..3] and COL[0..3],
2. resets the VIF1 state,
3. restores ROW[0..3] and COL[0..3],
4. continues the existing PS2Recomp reset logic for PATH2/PATH3 state.

The patch also injects regression assertions into `ps2xTest/src/ps2_memory_tests.cpp`.

GitHub Actions builds and executes the pinned `ps2x_tests` suite after applying the patch, so this compatibility behavior is tested rather than only checked textually.

## Scope

The current Downhill patch changes VIF1 only. The pinned PS2Recomp runtime does not model VIF0 register writes with the same detailed register structure in this path, so the project deliberately avoids adding an unverified VIF0 implementation as part of this compatibility fix.
