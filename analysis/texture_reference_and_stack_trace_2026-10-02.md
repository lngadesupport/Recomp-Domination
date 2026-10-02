# Checkpoint return correction and texture references — 2026-10-02

The corrected runtime advances beyond the reproduced invalid return into rider
selection, Start New Game and single-player mode selection. Three bounded
probes (100, 180 and 240 seconds) do not repeat the nonzero missing target or
stack-return anomaly. Colors and entry into a playable race remain unresolved.
The source fix and evidence are described below.

The restored source baseline is commit `7f7fea48370cb1ee0ed988b9bc19756b987f488d`.
The previous local build and unsaved four-routine tracing changes were lost
when the execution workspace restarted. This session restores and validates
those diagnostic changes; no result is claimed for the interrupted probe.

## Texture dump validation

The supplied `dumps.rar` has SHA-256
`73cde0338d6e6b6626a4ad6796348d1b626fc24ab37eb43c706cf806500b06dd`.
All 1,049 extracted PNGs decode successfully as RGBA. All dimensions match
the filename metadata and mip level: 416 64x64, 278 32x32, 208 128x128,
61 256x256, 51 16x16, 21 8x8, 10 128x64, 2 512x512 and 2 64x32.
PSM counts are 19:416, 20:629, 27:3, 36:1.

`scripts/inventory_texture_dumps.py` reproduces decoding, metadata parsing,
dimension comparison, pixel hashes and alpha ranges without changing pixels.
It accepts the full-texture names in this archive and explicitly rejects
unsupported region-name layouts. Pillow is required for image inspection.
The layout was checked against the primary PCSX2 source:
https://github.com/PCSX2/pcsx2/blob/master/pcsx2/GS/Renderers/HW/GSTextureReplacements.cpp

This is a reference inventory, not a runtime replacement loader. The current
runtime does not consume these PCSX2 hash names automatically. Comparison
requires identifying the corresponding live GS texture and palette. Texture
replacement also does not establish a correction for the invalid EE return.
The identified `replacements.rar` download repeatedly failed with HTTP 502;
its contents and image quality remain unverified in this session.

## Return tracing

The prior investigation retained a failure target/RA `0x1031210` and localized
its return branch to `0x204CD4`. These are earlier observations, not a new
probe result. The opt-in `PS2_TRACE_DOWNHILL_RESOURCE_RETURN=1` diagnostic now
wraps original routines `0x204C40` and `0x204CE0` and their call continuations,
in addition to `0x203D18` and `0x205F40`. It records entry arguments and expected
return SP/RA and samples unexpected stack restoration as an anomaly. The
original guest routines still execute unchanged. This instrumentation is
intended to distinguish saved-RA damage from incorrect stack restoration.

## Validation

42 Python tests pass, including mip metadata, TEXA fields, unsupported names,
corrupt images and preservation of PNG bytes/alpha. The override translation
unit passes GCC C++20 syntax validation against the patched pinned runtime.
The recompiled generator produces the expected 5,528 retail C++ files; retail
code and PNG assets remain outside this repository. The restored Release runner links successfully (44,598,656 bytes, SHA-256
`5b17c0e9efb158c353ed5982f2da94aeedcc187b3e440278b02585a9b0cb7e0f`).
All 2,335 restored game files pass size/CRC checks. The reconstructed diagnostic
ISO has 2,525,089,792 bytes and does not certify original disc layout. The
missing-target fixture passes enabled, disabled and malformed selectors.
Hosted runtime recovery checks pass on Linux and Windows for source commit
`e65ba81583bac4d8d3795037ebde19a1000642e5` (run 37070818818). The first restored 100-second navigation probe is not comparable: its
FFmpeg-disabled configuration differs from the previous working checkpoint.
It remained black, recorded no resource-return wrapper events and did not
reach the target failure. This configuration error was corrected before the subsequent comparisons. A playable race,
game FPS and Windows retail boot remain uncertified.

The preserved rider-visible checkpoint was separately rerun for 100.023 seconds
with the same X/Return/X/X navigation. It displays the main menu and reproduces
the dormant thread at PC/RA `0x1031210`; its runner identity remains
`c6a2b213631a0e88fa59cedec022cda8a8d61b445ab403f64ff16fde0e276fa3`. This restores
the reference failure in the new environment. The subsequent expanded trace comparison uses FFmpeg enabled.

## Checkpoint return regression

The expanded FFmpeg-enabled probe ran 100.037 seconds with runner SHA-256
`bb74b2ac9b785530cff3ad05cf5c7235506156fa48070bf3f0a71b4709703d22` unchanged.
The parent routine's failing call records saved RA `0x206C10` unchanged at
frame `0x93C910`, but exits with SP `0x93C890` instead of `0x93C920` (144 bytes
lower) and target `0x1031210`. This disproves saved-RA damage at that observed
parent frame; it does not by itself identify every preceding stack operation.

A synthetic fixture separately reproduces a dispatch defect: a callee that
returns at its entry PC after a checkpoint is mistaken for a completed inline
leaf. The old runtime returns `complete=1 pc=2000 sp=3ff0` although the caller
must remain paused at `pc=1000` with the callee's live stack. No retail code or
data is used by that fixture.

`ps2recomp-guest-checkpoint-return.patch` adds an EE-thread checkpoint serial.
The legacy inline-leaf completion rule applies only when no checkpoint was
returned while executing the callee. Both generated loop checkpoints and
nested dispatch checkpoints update that serial. Explicit completed-return
PCs retain their existing behavior. The regression fixture covers both yield
paths, normal inline leaves and an explicit completed PC after a checkpoint.
Fresh and repeated application of the pinned patch chain match SHA-256
`bfbcdb51ac043fabf6960da23aaf0c058129158f3217362443871ae4a03bcfe3`.
The synthetic fixture fails on the old runtime and passes all four cases on
the corrected production runtime. The corrected native build and after-fix probes are completed below. All 42 Python tests continue to pass.

## Corrected native navigation

The corrected FFmpeg-enabled Release runner is 44,620,840 bytes, SHA-256
`00cc2f233a5e60f00fc3edba95da0d9e82c5f5c24b714c8134386fa4759ec33b`.
The identical four-key navigation ran 100.047 seconds with unchanged binary
identity. It records no nonzero missing targets or resource-return anomalies.
The final snapshots retain a Ready thread at `0x238C50`, rather than a Dormant
thread in heap data. The 95-second capture shows **Rider Selected**, beyond the
previous freeze. This is a navigation milestone, not a playable-race or game
FPS certification. Colors remain visibly incorrect.

All four hosted workflows pass for source commit
`a95702ec6dc9732b24587b1bbabe25d2a2138829`: runtime recovery 37073273858,
production GS 37073273825, COP0 37073273844 and VIF/SDK/guest-checkpoint fixture
37073273838, including Linux and Windows component jobs.
The separate eight-key navigation ran 180.030 seconds with the same verified
runner. It records no nonzero missing target or resource-return anomaly. The
175-second capture shows **Start New Game**, beyond the rider selection. The
last snapshots remain Ready, not Dormant. The twelve-key navigation completed 240.039 seconds. Its 120-second capture
shows Single Player Game Mode (Single Event, Career, Arcade and other modes).
The 235-second capture has a mostly empty dark-red panel. No nonzero missing
target or resource-return anomaly is recorded, and the last EE thread remains
Ready at 0x238C50. This establishes further menu navigation, but does not
establish whether the last screen is loading, a graphics failure or a guest
progression issue. No playable race or game FPS is certified.

The rider triangle samples use TBP 8800, CBP 7362 and PSM 19. Sampled vertex
colors are not uniformly red, and fog and blending are enabled. The CBP 6805
filter instead observes TBP 128, PSM 36, index 2, RGBA 0x40000000. The earlier
zero-palette observation must not be generalized to the current rider texture.
No palette, fog or replacement-texture correction is claimed by this commit.
