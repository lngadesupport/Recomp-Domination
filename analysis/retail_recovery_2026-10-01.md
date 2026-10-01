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
- All runtime patches applied cleanly to a separate checkout of the pinned source and passed a second, idempotent application.

## Scope and remaining validation

The ISO is reconstructed from extracted files. Its internally consistent sector layout is a diagnostic fixture, not a verified copy of the original disc layout. Mount both this ISO and its matching extracted tree. The no-ISO EE/IOP virtual-sector mapping has not been fixed or validated here.

A first window attempt stopped during host initialization because the local X server lacked `xkbcomp`; its report correctly recorded no guest execution. After repairing the local display dependencies, a new 180-second probe loaded the ELF, all nine IRX modules and SKAT. Captures at 30, 90 and 175 seconds showed Sony, copyright and Incog opening videos respectively. The process reached its deliberate timeout with a stable runner SHA256 `e1c173109893b08e90df564216ee7a6741807fb3b46f3ce7021b5d4968f115e1`; it was not a crash or a completed game run.

All staged files were rechecked after copying: 2,335 CRCs matched. The fresh reconstructed ISO is 2,525,089,792 bytes. No menu, race, physics, native input, Windows runtime boot, or sustained 120 FPS claim is made by these tests.

Movie cancellation, IOP idle caching, and the resource-worker scheduling experiment remain absent from this checkpoint. A game-specific idle-wait experiment is being recovered separately below, disabled by default. It must not be described as a production 120 FPS fix.

## Scheduler and timing diagnostics

The ready-queue patch removes snapshot publication only when rotating a different priority's private FIFO, whose order is absent from the public snapshot. Current-thread rotation still publishes its changed state and requests rescheduling. All 32 focused kernel tests passed, including absolute priority/FIFO, same-priority rotation, immediate higher-priority preemption, waits, alarm completion, and semaphore transfers.

`PS2_TRACE_PERFORMANCE` reports host loop frequency and the EE-clock advance divided by wall time, using a synchronized kernel snapshot. `PS2_TRACE_BOOT_SNAPSHOT` reports thread PCs, priorities and wait states without enabling per-function logs. Host loop frequency and EE-clock ratio are diagnostics; neither is a measurement of rendered race FPS.

`PS2_DOWNHILL_IDLE_VSYNC=1` enables an experimental override for the dedicated endless rotation worker and three identified movie wait call sites (full output pool, final output drain, shutdown acknowledgement). It parks at existing VBlank events while retaining the scheduler clock. The normal guest helper is used at other call sites. This opt-in changes guest idle cadence and requires comparison with the original; it is not enabled by default.

## Reproduction

Use `scripts/recompile_downhill_headless.py`, then `scripts/build_downhill_posix.py --build-type Release --ffmpeg --quiet-function-trace`. Supply installed dependency paths with the existing `--prefix` and `--raylib-source` options. The build applies tracked version-pinned runtime patches. The Windows patch flow applies the same patches; these new Windows changes still require a compile check.

Use native unrar to extract the multipart archive, then `scripts/verify_extracted_disc.py` to verify and stage files. `scripts/build_extracted_probe_iso.py` creates the local fixture and records that original disc layout is unverified. These helpers require `rarfile` and `pycdlib` respectively.


## Timing experiment observed locally

A 60-second default run and 180-second idle-wait run used the same compiled runner and matching disc data, sequentially with no build running. The evidence directory records both raw logs and hashes. The default sample shows about 0.066 EE seconds per wall second while the host loop stays near 60 Hz. With the experimental movie/idle waits, stable opening/trailer samples approach 1.0 EE seconds per wall second. This is a clock/polling diagnostic on different phases of the opening flow, not a controlled race benchmark or a claim of 120 FPS. The attract clip is pre-encoded video, independently identified by FFmpeg as 640×368, 30000/1001 frames per second and 122.3222 seconds long.

After the trailer finishes naturally, thread 10 remains sleeping at the resource worker's initial `SleepThread` return (`0x231654`) and the main thread repeatedly waits on short alarm/semaphore intervals around `0x231214`. This recovers the post-movie loading blocker without requiring a movie-cancellation override.

`PS2_DOWNHILL_CD_READ_YIELD=1` is an additional diagnostic experiment, disabled by default. At the confirmed loader return `0x23147C`, it executes the existing host CD read and, only on success, defers the guest return to an existing VBlank with return value 1. It is not a DVD latency model. `PS2_TRACE_BOOT_SNAPSHOT` also wraps the original ReleaseWaitThread entry to record target state and original kernel result. Negative and positive probes are pending; no resource-worker race fix or menu validation is claimed yet.
