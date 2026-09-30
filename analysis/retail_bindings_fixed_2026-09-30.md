# Retail boot after correcting PAD/memcpy and CD search

Target: SHA-validated SCUS_971.77, PS2Recomp 75d729ce40d7eed9649fd4bb05628dee520f3d0c.

## Corrected bindings

| Address | Handler | Evidence |
|---|---|---|
| 0x002451B0 | scePadRead | Analyzer-recognized PAD wrapper; its internal call at 0x0024520C invokes memcpy. |
| 0x00254050 | memcpy | ELF instructions load/store quadwords from source to destination. The previous PAD alias replaced this memory-copy routine incorrectly. |
| 0x00246FA0 | game-specific sceCdLayerSearchFile | Retail wrapper preserves a0=file, a1=path, a2=layer and binds CD file-search SID 0x80000597. Layer zero now uses the existing real ISO/extracted-disc search backend. Unsupported layers return failure. |
| 0x0025C440 | sceSifSendCmd | Existing SIF binding retained. |

This corrects the earlier interpretation of the JAL at 0x0024520C. A call from a PAD function does not make its target a PAD API.

The CD override performs a real lookup. It never invents an LBN or reports success for a missing file. It is scoped to the SHA-validated retail build through the existing CRC-bound game override.

## Local verification

- Regenerated 5,528 retail C++ files. PAD, memcpy and SIF stub bodies were checked at their respective addresses.
- Linked the native Linux diagnostic runner: SHA256 a111243a7ea2a91a14d5ebf3d5d4fa8b7d2af234147b76b5305d4ece4fd3ccd5.
- Two bounded guest probes (35 seconds and 20 seconds) passed the old CD RPC bind loop.
- Nine physical IRX modules loaded, with no module-open/load failure, HLE fallback or unhandled RPC recorded.
- The guest requested `\SKAT\DHSKAT.SKX;1`; this file is absent from the local IRX-only disc tree. The IOP reported an audio-bank read error.
- Counters advanced to DMA=4, VIF=2 and GIF=1; two GS register events were logged. This is graphics command traffic, not evidence of a menu or playable race.
- The framebuffer captured at seven seconds still shows the runtime's initial magenta texture. No game menu was rendered. PS2Memory's reset DISPLAY1/DISPFB1 pair is excluded from both triage and suggestions.
- The guest subsequently remains at PC 0x0025A308, RA 0x001DF5E0, after its bank-load failure/exit path.
- Triage now reports `cd-file-search` with the exact failed path instead of classifying ordinary SIF activity as the current blocker.
- Five triage fixtures passed, including CD search after early graphics and reset-display handling. Readiness tests passed and reject the historical PAD/memcpy collision.

Both uploaded copies of the first multipart RAR volume were retried. Neither could be made available: both failed with HTTP 502. Proprietary data and generated retail code remain local.

## Current limit

Menus and races are not validated. Further retail progression requires accessible full original disc data, beginning with DHSKAT.SKX. See docs/GAME_VALIDATION.md for the coverage requirements after the menu is reachable.

## Windows checks

The portable Clang/LLVM build at commit a9dd947d4d913b9f4633637dad9c5d4c6de21fd5 passed, including the new game override and a clean offline compiler/analyzer/synthetic-runtime build: https://github.com/lngadesupport/Recomp-Domination/actions/runs/36753367647.

The MSVC isolated override compile initially lacked the runtime Kernel include directory. That CI command was corrected; the isolated compile passed in run 36753988370. The full MSVC upstream regression build was still running when this checkpoint was recorded. Retail guest execution evidence above comes from Linux, not a Windows retail playtest.
