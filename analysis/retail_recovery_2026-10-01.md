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

Movie cancellation and IOP idle caching remain absent from this checkpoint. The game-specific idle-wait and resource-worker scheduling experiments described below are disabled by default. They must not be described as production 120 FPS fixes.

## Scheduler and timing diagnostics

The ready-queue patch removes snapshot publication only when rotating a different priority's private FIFO, whose order is absent from the public snapshot. Current-thread rotation still publishes its changed state and requests rescheduling. All 32 focused kernel tests passed, including absolute priority/FIFO, same-priority rotation, immediate higher-priority preemption, waits, alarm completion, and semaphore transfers.

`PS2_TRACE_PERFORMANCE` reports host loop frequency and the EE-clock advance divided by wall time, using a synchronized kernel snapshot. `PS2_TRACE_BOOT_SNAPSHOT` reports thread PCs, priorities and wait states without enabling per-function logs. Host loop frequency and EE-clock ratio are diagnostics; neither is a measurement of rendered race FPS.

`PS2_DOWNHILL_IDLE_VSYNC=1` enables an experimental override for the dedicated endless rotation worker and three identified movie wait call sites (full output pool, final output drain, shutdown acknowledgement). It parks at existing VBlank events while retaining the scheduler clock. The normal guest helper is used at other call sites. This opt-in changes guest idle cadence and requires comparison with the original; it is not enabled by default.

## Reproduction

Use `scripts/recompile_downhill_headless.py`, then `scripts/build_downhill_posix.py --build-type Release --ffmpeg --quiet-function-trace`. Supply installed dependency paths with the existing `--prefix` and `--raylib-source` options. The build applies tracked version-pinned runtime patches. The Windows patch flow applies the same patches; the isolated Windows compile checks passed as described below; a full Windows runtime link and retail boot remain unverified.

Use native unrar to extract the multipart archive, then `scripts/verify_extracted_disc.py` to verify and stage files. `scripts/build_extracted_probe_iso.py` creates the local fixture and records that original disc layout is unverified. These helpers require `rarfile` and `pycdlib` respectively.


## Timing experiment observed locally

A 60-second default run and 180-second idle-wait run used the same compiled runner and matching disc data, sequentially with no build running. The evidence directory records both raw logs and hashes. The default sample shows about 0.066 EE seconds per wall second while the host loop stays near 60 Hz. With the experimental movie/idle waits, stable opening/trailer samples approach 1.0 EE seconds per wall second. This is a clock/polling diagnostic on different phases of the opening flow, not a controlled race benchmark or a claim of 120 FPS. The attract clip is pre-encoded video, independently identified by FFmpeg as 640×368, 30000/1001 frames per second and 122.3222 seconds long.

After the trailer finishes naturally, thread 10 remains sleeping at the resource worker's initial `SleepThread` return (`0x231654`) and the main thread repeatedly waits on short alarm/semaphore intervals around `0x231214`. This recovers the post-movie loading blocker without requiring a movie-cancellation override.

`PS2_DOWNHILL_CD_READ_YIELD=1` is an additional diagnostic experiment, disabled by default. At the confirmed loader return `0x23147C`, it executes the existing host CD read and, only on success, defers the guest return to an existing VBlank with return value 1. It is not a DVD latency model. `PS2_TRACE_BOOT_SNAPSHOT` also wraps the original ReleaseWaitThread entry to record target state and original kernel result. The negative/positive comparison is complete. Both runs used stable runner SHA256 `8450f2017948aac92d44beb8facc0d6547f8ac8f4c668c602e3054a9bfc2ded7`. Without the yield, target 10 was Ready (status 1) and the original ReleaseWaitThread returned `-416` (`KE_NOT_WAIT`). With the yield, target 10 was Waiting (status 2), the original operation returned 0, and the worker began processing resources. This confirms the initialization race caused by removing the native read wait. The diagnostic is kept opt-in; a production async-CD model and original timing comparison are still required.

After this advance, the main thread waits on semaphore 8 at return `0x23144C`. Worker 10 remains Running; its published snapshot repeatedly shows `memcpy` with return `0x240BB4` in the resource processing function at `0x2407F8`. The menu has not appeared. The next investigation should capture copy lengths, input/output offsets and buffer contents on the guest executor, check decoder progress, and validate those inputs against the verified SKAT container. A snapshot PC alone does not prove the active instruction or an infinite loop.


## Cross-platform verification

[Runtime recovery CI](https://github.com/lngadesupport/Recomp-Domination/actions/runs/36822433697) passed for Ubuntu and Windows on source checkpoint `ea26dfc531d203f64d9f9394f865ddb38aa0c2e6`. It applied the five runtime patches twice, ran all six Python watchdog/identity regressions on Ubuntu, parsed the PowerShell scripts and exercised the canonical Windows patch flow, and compiled the override, GS, MPEG fallback configuration, IOP CDVD, and EE scheduler translation units with MSVC. The first attempt lacked raylib headers in the isolated compile environment; the pinned header dependency fixed the test setup. This is an isolated compile check, not a new Windows runtime link or Windows retail boot claim.


A final 420-second run used the same stable `8450f201...` runner with both diagnostics enabled. The loader still had not reached a menu at 415 seconds. Thread 10 remained Running and the main thread continued waiting on semaphore 8; the last measured EE-clock ratio was about 0.087 while the host loop stayed near 60 Hz. The window contained a small region of incomplete/corrupt image data, not a menu. This establishes a subsequent processing/decoder blocker after the confirmed initialization-race advance. Raw logs, the timeout report, and the final capture are retained under `analysis/evidence/2026-10-01-resource-worker`.

## Resource-copy diagnostic continuation

The next session recovered source checkpoint `70ea85d` from GitHub after the scratch environment reverted to an older source tree. The verified disc data, display dependencies and native probe runner were no longer present. No new retail execution is claimed.

`PS2_TRACE_RESOURCE_COPY=1` now wraps the already bound memcpy handler only at return `0x240BB4`. It calls the same existing stub and preserves its guest return and memory semantics. On the guest executor it records copy length, source/destination, worker ID, s1 input offset, s5 output-after value, s6 remaining-after value, fp window, the two dictionary/output base globals, pre-copy source bytes and post-copy destination bytes (at most 16 each). The JAL delay slot has already advanced s5 and s6 was decremented before the call. Static inspection shows this branch handles dictionary/back-reference copying, so source bytes must not be treated as the compressed SKAT input. The overlap branch at `0x240BC0` remains original guest code.

Only calls 1–64 and subsequent powers of two are logged; the cumulative zero-copy counter includes unsampled calls. The trace is disabled by default, reads no MMIO and does not impose a new scheduler wait. It can affect diagnostic timing when enabled. `scripts/analyze_resource_copy_trace.py LOG` summarizes records and flags malformed data, return-pointer mismatches, existing stub size clamps, missing source samples and byte-sample differences. Raw address ranges do not establish physical non-overlap because guest aliases can coincide. Sample differences and zero-length copies are observations, not proof of a decoder bug or infinite loop.

Validation: the override passed a local GCC C++20/AVX2 syntax compile against the runtime headers. All 11 Python tests passed, including five new trace-analysis cases covering normal copies, zero copies, sampling gaps, malformed/truncated records and counter restarts. These are diagnostic/parser checks; no new game boot, menu, race or FPS result is asserted. The next native probe should enable this trace alongside the existing two opt-in scheduling diagnostics and retain the runner's before/after SHA256.

Cross-platform follow-up: [CI run 36848505768](https://github.com/lngadesupport/Recomp-Domination/actions/runs/36848505768) passed both Ubuntu and Windows jobs for source checkpoint `f71197bcc35d849648152f8d62519f411622f767`. The new wrapper compiled with MSVC and all 11 Python tests passed on Ubuntu. This retains the isolated compile limitations of the previous CI; no full runtime execution is inferred.

## Confirmed leaf-handler continuation fix

The native reproduction recovered all 17 original archive volumes, passed native unrar integrity checking, and verified all 2,335 staged files against size and CRC again. Regeneration produced 5,528 C++ units with the required dispatch entries. Both tested runners were Release/FFmpeg builds with function tracing off and the existing idle/CD-read diagnostics enabled.

Before the fix, the copy trace's sampled counter reached 268,435,456. Later sampled calls repeatedly had length 4, source 11,295,383, destination 11,299,809, input offset 23,191 and output-after 27,621, with equal source/destination byte samples and no zero-length copies. The worker snapshot remained at host memcpy entry 0x254050, RA 0x240BB4. Inspection showed the generated wrapper establishes ctx->pc from RA before invoking a host stub, while the game's direct address override omitted that step. An EE safe point immediately before the call can resume at the host entry; the raw stub then returns without advancing PC and the dispatcher invokes it again. This identifies a guest continuation bug, rather than evidence of bad copy sizes or compressed input.

The game-specific leaf adapter now establishes the return PC before calling the existing host handler and preserves any subsequent PC transfer made by that handler. It covers memcpy, pad, SIF command, the two MPEG queries and layered CD search. The diagnostic memcpy wrapper uses the same adapter. POSIX and Windows build flows stage the adapter header. A native C++ regression exercises direct and nested invocation, argument/result preservation and an explicit handler PC transfer. Ubuntu and Windows [CI run 36851340945](https://github.com/lngadesupport/Recomp-Domination/actions/runs/36851340945) passed, including that executable regression and the 11 Python tests.

After the fix, copy sizes/offsets/bases changed across samples, workers 11–13 advanced, and the main thread resumed. The subsequent persistent snapshot was PC 0x1B4648, RA 0x1EBEEC. Static inspection maps that PC to a loop waiting for globals 0x29E1C8, 0x29E1CC and 0x29E1E4; the clearing routine at 0x21E9A8 starts a VIF1 DMA transfer. Native observations have not yet established which flag stays set or the relevant DMA/interrupt ordering. Audio initialization also reports an IOP stream-buffer allocation failure; its cause and relationship to the main wait are not established. The 235-second capture shows corrupted cyan/orange rendering, not a usable menu.

Both 240-second probes reached their deliberate timeout with stable before/after executable hashes: before 90247388cf9ef7acda1c03a5fa85119a56c8ea3775b21925e0be57708fd5711d; after 101999da1af043414d3f4006e76d714f5602b50808f3d0233bd83501289ec821. The original runner was copied before rebuilding; the rebuild overlapped the last part of the negative probe, so these runs are behavioral evidence, not a controlled performance benchmark. Raw evidence is under analysis/evidence/2026-10-01-leaf-continuation. Menu, racing, native input, Windows retail boot and 120 FPS remain unverified.
