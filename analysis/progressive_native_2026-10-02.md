# Progressive native diagnostics — 2026-10-02

The Linux Release runner is built from the pinned runtime and verified retail generation, with FFmpeg and without aggressive function logging. Its retained SHA256 is `343b40ce0200d1b602cf4b20b93c98111612b2d2efa60ff5bf2cca0b245bb6a0`. All 2,335 extracted non-tool files (2,520,670,702 bytes) and their staged copies passed archive CRC checks. The diagnostic ISO is reconstructed from these files; it is not an original disc-layout dump.

## Completed validation

- 34 Python regressions passed, including five new progressive-runner tests.
- The actual production renderer passed the 20-case CLUT and 168-case 24-bit upload fixtures under ASan/UBSan.
- Seven additional production trace-filter scenarios passed, giving nine CTest entries in total: matching CBP, other CBP, empty selector, negative selector, out-of-range selector, huge selector and trailing text.
- The complete pinned patch series applied to a clean checkout and reapplied successfully.
- Verified native probes completed their requested 180 seconds (Debug), 60 and 120 seconds (Release), and 90 seconds (Release with palette/image diagnostics). Deadline SIGKILL is intentional, not an observed native crash. These establish guest execution only.

## New observation

The palette diagnostic reached PSMT4HL font samples at TBP=128 and CBP=6805. All 64 bounded nonzero-index samples returned RGBA=0. Earlier palette-load records were consumed by CBP=6753; those sampled entries were also zero. This narrows the investigation but does not prove that VRAM uploads, CLUT storage, or address decoding caused the invisible font.

The trace patch now accepts optional `PS2_TRACE_GS_CLUT_CBP=6805` together with `PS2_TRACE_GS_CLUT_LOADS=1`. The selector is decimal, 0–16383. Missing selector preserves the existing all-palette diagnostic; malformed selectors emit no matching records. Unrelated palettes no longer consume the selected palette's bounded trace counters. Rendering behavior is unchanged.

Snapshots repeatedly show PC/RA=0x238C50 at sceGsSyncV continuation, alternating between VSync wait and readiness. DMA/GIF counters advance and displayed framebuffers alternate. These observations do not establish scheduler deadlock. Release captures remain black; no playable menu or race has been validated.

## Long-run executor

`scripts/run_native_progression.py` runs fixed-configuration probes with increasing durations, preserves each result, caps logs, stages disc sidecars beside the ELF, owns/cleans up Xvfb, and checks the runner against a retained successful-build hash before and after each probe. Identity change or host/boot failure stops the batch. A normal probe timeout permits the next run. It never promotes host tick frequency to game FPS.

The 7,500-second batch was started with schedule 60,120,240,480,600 seconds, repeating the final duration, and a maximum of 32 probes. At this report snapshot, 60-, 120- and 240-second runs were complete and the batch was still running. This report does not certify completion of two hours. The live local summary is `analysis/local/native-125min-release-v2/summary.json`; each completed run remains independently reviewable.

No 60 FPS, 75 FPS, Windows retail execution, or playable gameplay is certified. Concurrent diagnostic runs use software graphics and cannot support a fair performance comparison. Public evidence excludes retail assets and generated retail C++.

## Hosted checks

Source commit `97841498c251cc6e6ba430f24b4097d52dee73f6` passed the production renderer workflow on Linux and Windows (run `36946671981`) and runtime recovery checks (run `36946671875`). COP0 regression run `36946671855` also passed. The Release checkpoint runner predates the optional CBP-filter addition and corresponds to source commit `955dc65b19249ff31fe7824fe4f237d691ebf8a3`; it is the fixed executable used by the long batch.

## Targeted native result

The CBP-filtered runner SHA256 `40c88187a4183f7171b4fb4500f7fb472700a448fe3c832799b2192a2e04b2f5` completed a verified 90.027-second native probe. It logged 384 sampled palette-load entries at CBP=6805 (entries 0, 8 and 15 across 128 forced loads), all raw=0, and 64 nonzero-index font samples, all RGBA=0. This confirms that sampled zero colors are already present at the actual palette-load reads rather than being inferred from an early unrelated palette. Entry 1 was not included in the load sampler. It does not distinguish absent uploads from incorrect upload addressing, incorrect palette-read addressing, or other upstream defects. The image remains black.
