# Downhill Domination compatibility notes

Target: Downhill Domination NTSC-U, `SCUS-97177`, validated retail ELF.

This file records compatibility clues that are useful during native bring-up. They are **diagnostic evidence, not automatic guest patches**. Do not apply a workaround unless the native runner reproduces the corresponding failure mode.

## VIF/VU history

PCSX2 issue #1218 documented a Downhill Domination shadow regression introduced by a VIF change. The fix landed in PCSX2 commit `6649f43069318605e48ccc199ec7ec6c75e25f02` with the summary:

> VIF: Only delay MSCAL - Fixes #1218 Downhill Domination and Twisted Metal Head-On.

The historical change forced the VIF execution queue for `MSCALF` and `MSCNT`, while preserving the special delayed handling only for `MSCAL`.

Source:
- https://github.com/PCSX2/pcsx2/issues/1218
- https://github.com/PCSX2/pcsx2/commit/6649f43069318605e48ccc199ec7ec6c75e25f02

The pinned PS2Recomp runtime currently processes `MSCAL`, `MSCALF`, and `MSCNT` directly in the VIF1 interpreter and invokes VU1 callbacks synchronously. `PS2Runtime` calls `VU1Interpreter::execute` / `resume` inside those callbacks with a bounded 65,536-step budget. Therefore the first Downhill build should **not** add an extra asynchronous VU1 layer or an emulation-style VU cycle-stealing hack.

## Additional historical timing clues

Community PS2-on-PS4 compatibility work for `SCUS-97177` reported graphics improvements with:

- VIF1 instant transfer disabled;
- synchronized VU1 execution;
- VU1 MPG timing around 3300-3500 cycles;
- adjusted EE/IOP/CDVD timing.

These values come from a different emulator and are not portable constants for this recompilation. Treat them only as a triage clue if the native runtime reaches gameplay with geometry corruption, missing VU output, or loading/timing stalls.

Reference:
- https://www.psx-place.com/threads/research-ps2-emulator-configuration-on-ps4.16131/page-140
- https://www.psx-place.com/threads/research-ps2-emulator-configuration-on-ps4.16131/page-141

## Known guest-code anchor

The validated NTSC-U ELF contains:

```text
0x00243D34 = 0x30420001
```

Community deinterlace patches replace it with `0x30420000`. Keep the original instruction during correctness bring-up. Deinterlacing is cosmetic and must not be mixed with boot-critical fixes.

## What to watch during first boot

| Symptom | First subsystem to inspect |
|---|---|
| Function-table miss / exact guest PC not registered | Ghidra function boundaries and entry-point discovery |
| Boot reaches file access then stalls | CD/DVD VFS, IOP modules, SIF/RPC |
| No controller response | `scePadRead` binding and pad state |
| Geometry explodes / shadows produce long triangles | VIF1 command ordering, VU1 synchronization, TOP/TOPS/ITOP/ITOPS state |
| VU output missing after microprogram upload | VIF1 MPG handling and VU1 code invalidation |
| Frame reaches GS but output is corrupted | GIF path arbitration / GS transfer semantics |
| Intro/FMVs stall before menu | MPEG/IPU path; FFmpeg is intentionally disabled in the first bootstrap |
| Menu is usable but presentation is interlaced | Leave correctness path untouched; handle deinterlace later |

## Current project policy

1. Keep `patch_syscalls = false`, `patch_cop0 = false`, and `patch_cache = false` for the initial retail build.
2. Preserve generic analyzer patches such as detected self-modifying stores when emitted.
3. Prefer the Ghidra CSV/TOML for retail function boundaries and runtime-known symbol classification.
4. Do not add EE/IOP/VU timing scalars from another emulator without a reproduced native-runtime symptom.
5. Keep widescreen, deinterlace, 60 FPS and other presentation patches out of the correctness baseline.
