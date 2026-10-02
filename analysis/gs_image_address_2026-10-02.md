# SDK image base-address correction — 2026-10-02

The native zero-palette observation is now traced to a concrete SDK handler defect. `sceGsExecLoadImage` and `sceGsExecStoreImage` multiplied the descriptor's GS block address by eight before packing BITBLTBUF. The descriptor already uses 256-byte blocks. Both handlers now preserve its address; framebuffer page conversions elsewhere are unchanged.

## Evidence

| Observation | Before | After |
|---|---|---|
| Palette 6753 upload destination | `(6753 * 8) & 16383 = 4872` | 6753 |
| Palette 6805 upload destination | `(6805 * 8) & 16383 = 5288` | 6805 |
| Instrumented writes to physical block 6805 | 0 | 16 |
| Entry 1 palette reads | 128 reads, all zero | 128 reads, all 721420288 |
| Sampled nonzero texture indices | 64 colors zero | 64 colors nonzero |

The original diagnostic runner (`636a409e...`) completed a verified 90.061-second probe. All 512 sampled reads of entries 0, 1, 8 and 15 at CBP 6805 were zero. Its 128 bounded small CT32 upload records included the misdirected font palette at DBP 5288. The physical watch recorded no writes to block 6805.

The corrected runner (`dd2db4b1bd0670079afde8797416287ee8913c61e9cbd8da4222dfbcce496035`, 44,590,112 bytes) completed a verified 90.027-second probe. It uploaded 64 bytes to DBP 6805, recorded all 16 physical writes, and loaded the expected entry-1 color. Half of the 512 sampled palette entries were nonzero; transparent entries 0 and 15 legitimately remained zero. All 64 nonzero-index texture samples produced nonzero RGBA.

Captures show copyright content, a visible “Press X to Start” prompt, and later “Demo / Red Pass, Utah FR” text. The demo still has corrupt geometry/backgrounds. This fixes the confirmed image-address and font-palette defect, not all rendering. No playable race or game FPS is certified.

The restored older runner (`40c88187...`) also completed an 88.033-second identity-verified probe. Its final capture contained partially corrupted loading text, showing that earlier black captures were not a universal outcome. Concurrent software-rendered diagnostic executions are behavioral evidence, not performance comparisons.

## Regression checks

- Four nonzero addresses (1, 6753, 6805, 16383) pass through the actual production SDK upload and readback handlers. Direct GS memory accesses independently anchor both operations; a symmetric roundtrip cannot conceal a shared address error.
- Restoring the old upload conversion fails the fixture with exit 3. Restoring only the old readback conversion fails with exit 4.
- The production renderer passes 20 CTest entries under ASan/UBSan. The new palette fixture covers 72 configurations and all 16 color indices: direct and aliased bases, CT32 host chunks, four-bit indexed formats, and the final VRAM block. The physical-watch fixture also checks all 13 implemented storage formats, alias addresses, wrap, and malformed selectors.
- All 34 existing Python regressions pass.
- The complete patch series applies to a fresh pinned checkout and reapplies with an identical tracked diff. POSIX and canonical Windows patch flows both include the address correction and diagnostics. Windows execution is not asserted by local Linux checks.
- All 17 restored RAR volumes passed native archive verification. All 2,335 extracted and staged files passed size/CRC comparison. Generation produced the expected 5,528 C++ units. The ISO remains a reconstructed diagnostic fixture, not an original-layout dump.

## Reproduce

Build using the existing POSIX or Windows flow. The independent SDK fixture can be linked against an already completed POSIX runtime build:

```sh
python3 scripts/test_gs_sdk_image_address.py --source /path/to/PS2Recomp --build /path/to/native-build --output /path/to/sdk-fixture
```

Optional diagnostics, disabled by default:

- `PS2_TRACE_GS_CLUT_LOADS=1 PS2_TRACE_GS_CLUT_CBP=6805` includes entry 1 without unrelated palettes consuming its existing budget.
- `PS2_TRACE_GS_VRAM_BLOCK=6805` watches physical byte addresses, including writes through different base registers. It emits the first 128 matches and subsequent powers of two. Bulk resets/direct VRAM writes outside the production storage functions are not intercepted.
- `PS2_TRACE_GS_PALETTE_UPLOADS=1` samples the first 128 CT32 uploads with buffer width 1, rectangle width at most 16, and at most 256 pixels. These are candidate palette-shaped transfers, not semantic proof that every record is a palette.

The image-address correction is unconditional. Diagnostics preserve normal writes and rendering. The extra entry-1 sampler performs an additional read under the backend lock. Raw public evidence excludes game assets and generated retail C++.

For independent register-unit context, the [ps2dev gsKit texture sender](https://github.com/ps2dev/gsKit/blob/master/ee/gs/src/gsTexture.c) packs both texture and BITBLTBUF addresses in byte-address/256 units.

## Input continuation

A further identity-verified 140.010-second native probe used the same corrected executable. An XTest controller in the probe's own Xvfb namespace sent Space, Return and Space, holding each for one second and recording each event's UTC time. Captures at 70 and 135 seconds show Single Player / Multi-Player / Options and Player One / Select Rider text. This establishes a visible menu transition following input, not a complete menu or race certification: models/backgrounds remain absent and interface layers overlap. The 180-second first input attempt received no keys because its controller ran outside the probe's display namespace; it is excluded from input-response evidence. The retry kept the controller and probe in the same execution context.

## Hosted validation

The production renderer workflow passed on Linux and Windows (run [37004910277](https://github.com/lngadesupport/Recomp-Domination/actions/runs/37004910277)); the COP0 DMA condition workflow also passed (run [37004910302](https://github.com/lngadesupport/Recomp-Domination/actions/runs/37004910302)).

The first recovery workflow exposed a Windows PowerShell 5 failure in expected negative reverse-patch checks. The canonical script now suppresses native stderr only for those checks and restores its error preference before applying patches. At source commit `9bdf5fc2525e488a11bb79fbeecc986de276c822`, recovery run [37005364982](https://github.com/lngadesupport/Recomp-Domination/actions/runs/37005364982) passed on both Linux and Windows, including MSVC handler compilation and 100,000 native cases per platform. This validates the patched runtime components, not a complete Windows game executable or playable race.
