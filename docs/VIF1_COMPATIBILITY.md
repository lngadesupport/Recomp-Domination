# Downhill Domination VIF FBRST compatibility note

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

The compatibility patch now covers the documented FBRST behavior for both VIF units.

For VIF0, the pinned PS2Recomp previously accepted writes in the VIF0 register range but did not apply FBRST at 0x10003810. The patch now implements only the validated FBRST subset needed here:

- RST clears modeled VIF0 command/status state while preserving ROW/COL.
- STC clears the modeled stall/interrupt status bits 8..13.

It deliberately does not invent unverified VIF0 force-break, DMA cancellation, FIFO flushing, or additional register behavior. Those remain evidence-driven bring-up work if the retail trace reaches them.

Both VIF0 and VIF1 behaviors are covered by the PS2Recomp regression suite after the patch is applied.
