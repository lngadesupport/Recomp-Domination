# Nonzero guest target and inactive EE snapshots — 2026-10-02

The navigation failure is now localized to an attempted dispatch into guest data. This is a diagnostic finding, not a gameplay correction.

## Verified probe

Runner SHA-256 `46df8c7031b95262359af34ddefe1d11b254dfba68b2f9a10a56d228e6d9df25`, Linux Release, 100-second limit, unchanged before/after. X, Return, X, X used one-second holds and 15-second gaps. Intro-skip, idle VSync and resource CD yield experiments remained enabled as in previous probes.

The first nonzero missing-target event is the scheduler at PC and RA `0x1031210`. The runtime says codeRegion=no; the dense generated function table has no entry at this target. The saved address is inside the guest RAM data range and its sampled words contain resource pointers. The last dispatch-history entry is `0x203D18`, following `0x205F40`. These observations localize the failure but do not yet distinguish a damaged saved return address from an incorrect continuation.

Repeated final snapshots show running=0 and only thread 1, status 5 (Dormant), at the same PC. DMA/GIF counts stop advancing. An open presentation window is therefore insufficient proof of continued game execution.

The SDK pad uses `runtime->padBackend().readState` first. Its actual PSPadBackend accepts both X and Space; the fallback SDK keyboard mapping alone does not establish which path was used. Changing Space to X did not resolve this failure.

## Retained diagnostics

`PS2_TRACE_GUEST_MISSING_TARGETS=1` preserves the existing first missing-target report and samples the first 32 **nonzero** target events plus powers of two. Zero invocation-return sentinels do not consume that budget. It includes four target words using the existing bounded guest-memory reads. Disabled/malformed selectors preserve original first-report behavior and target-PC policy. Diagnostic logging can change wall-clock timing.

`analyze_guest_progress.py` now retains valid thread snapshots and reports repeated all-dormant observations only for increasing host ticks and two complete consecutive records. Ready, waiting, running, malformed or truncated records do not establish this condition. Boot observation remains separate from menu, race and FPS certification.

A second 100-second identity-verified probe (`2a3e4e9a16032180cba27a7b1c8416ac30c4c2fa49fc55a52f6428ab21e07e9f`) wraps original routine `0x203D18` and its three call continuations. Sampled returns preserve saved RA `0x206020`; no wrapper anomaly was recorded, yet the same scheduler failure recurs. The last called routine alone cannot be identified as the corruption site. The expanded opt-in `PS2_TRACE_DOWNHILL_RESOURCE_RETURN=1` also wraps caller `0x205F40` and its four continuations. It reads saved RA before/after normal execution and does not replace guest logic. The missing-target diagnostic also reports `branch_pc` to recover the source hidden by a scheduler checkpoint.

## Validation

38 Python tests pass, including incomplete/malformed snapshot and dormant-state cases. The real-runtime missing-target fixture passes enabled, disabled and malformed selectors, 65 zero-return sentinels before the real target, bounded sampling, readable/null target memory and preservation of PC. Fresh application and second application of the complete pinned patch chain produce identical changes.

Source commit `098f97a3c68d5c863e90387405156736d8b17fa0` passes hosted runtime recovery, production GS, COP0 and VIF/SDK/trace workflows on Linux and Windows. These are component checks; neither a playable race nor Windows retail boot is certified.
