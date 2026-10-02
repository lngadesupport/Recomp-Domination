# Texture references and expanded return diagnostics — 2026-10-02

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
code and PNG assets remain outside this repository. Native probe results are
pending the restored Release build and verified disc data. A playable race,
game FPS and Windows retail boot remain uncertified.
