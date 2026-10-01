# Retail source and data recovery — 2026-10-01

## Confirmed in this session

- Restored the source contents of remote compiler checkpoint `d5e0604ac67644ad6a488a5590d45a3eb8a0c3ad`. Earlier uncommitted runtime experiments were absent from the workspace.
- Recovered all 17 user-provided archive volumes. Native unrar's archive test succeeded. Verified 2,335 non-tool game files, totaling 2,520,670,702 bytes, against member sizes and CRC32 values. No game files are committed.
- Rebuilt a fresh uppercase disc tree and diagnostic ISO. A stale truncated `R/TSH.NGP` in the earlier staging directory was detected; the fresh file is 62,853 bytes and matches archive CRC32 `BDA1349D`.
- Recompiler generated 5,528 C++ files and verified 20 required entries plus the PadRead, memcpy, and SifSendCmd bindings. Twelve graphics dispatch targets already existed; interior entries `0x2627A0` and `0x2628A0` now have function-table aliases and resume labels.
- Linux Release runner linked with actual FFmpeg decoding enabled and aggressive per-function logging disabled. Build identity: ELF SHA256 `adfda7b73a8f05fb20a3f0f318772e9d3797fd4d6c0a6c0078ae392df0f0cf0c`; PS2Recomp pin `75d729ce40d7eed9649fd4bb05628dee520f3d0c`.
- All 73 focused GS tests passed, including one MiB CT32 upload/readback across IMAGE tag boundaries and preservation of guest heap/stack scratch.
- Physical ISO lookup test compared all bytes of SKAT, a real IRX, the opening video, and `R/TSH.NGP` to extracted files. Missing files, parent traversal, and an invalid volume descriptor were rejected.
- MPEG regression passed: terminal PSS program marker is accepted before padded CD producer EOF, queued pictures delay completion, new stream generation resets completion, and sequence end alone does not end playback.
- Two probe identity regressions passed, including a child replacing its own runner. Reports retain both pre-run and post-run hashes.
- All three runtime patches applied cleanly to a separate checkout of the pinned source and passed a second, idempotent application.

## Scope and remaining validation

The ISO is reconstructed from extracted files. Its internally consistent sector layout is a diagnostic fixture, not a verified copy of the original disc layout. Mount both this ISO and its matching extracted tree. The no-ISO EE/IOP virtual-sector mapping has not been fixed or validated here.

A first native window probe stopped during host initialization because the local X server lacked `xkbcomp`; no guest execution was reported by that attempt. Window boot and post-intro loading remain to be retested once the virtual display is complete. No menu, race, physics, native input, Windows runtime boot, or sustained 120 FPS claim is made by these tests.

Earlier proposed movie cancellation, game-specific idle waits, IOP idle caching, and a resource-worker scheduling experiment were not present in the recovered source. They are not part of this checkpoint. The next retail blocker must be measured again using the rebuilt runner and fresh disc fixture.

## Reproduction

Use `scripts/recompile_downhill_headless.py`, then `scripts/build_downhill_posix.py --build-type Release --ffmpeg --quiet-function-trace`. Supply installed dependency paths with the existing `--prefix` and `--raylib-source` options. The build applies tracked version-pinned runtime patches. The Windows patch flow applies the same patches; these new Windows changes still require a compile check.

Use native unrar to extract the multipart archive, then `scripts/verify_extracted_disc.py` to verify and stage files. `scripts/build_extracted_probe_iso.py` creates the local fixture and records that original disc layout is unverified. These helpers require `rarfile` and `pycdlib` respectively.
