# Geometry pipeline preparation — 2026-10-03

Two reproducible VIF transport defects are fixed before starting any new
retail game probe. These are actual production-runtime regressions, not
proof that every native graphical defect is resolved.

| Patch | Before | Prepared behavior |
| --- | --- | --- |
| `ps2recomp-vif-mpg-continuation.patch` | An MPG payload split across transfers could be dropped; its next fragment could be decoded as VIF commands. | Both VIF channels retain the remaining byte count and upload destination, consume continuation bytes before commands, and invalidate the VU code cache on writes. |
| `ps2recomp-vif-unpack-continuation.patch` | An incomplete UNPACK payload could be skipped; subsequent vertex data could be interpreted as commands. | Both VIF channels retain a bounded command/payload buffer and call the existing UNPACK decoder only when its complete payload arrives. Following commands remain aligned. |

Initialisation cancels pending MPG and UNPACK state in both channels.
VIF1 FBRST cancels both continuations; its existing ROW/COL compatibility
behavior remains in the build path. The UNPACK buffer is bounded by one
command plus the largest NUM=0 V4-32 payload (4,100 bytes). This patch does
not add handling for fragmented command headers or unrelated commands.
It preserves existing destination clipping, decode formats and MODE/mask
semantics; it does not establish their full hardware correctness.

The original code fails the MPG fixture at VIF1/count=1/split=4. With MPG
fixed, the original UNPACK path fails VIF1/scalar32/count=3/cycle=1:1/split=4.
The corrected runtime passes 1,055 MPG cases and 36,710 UNPACK split/whole
geometry cases, plus an independently specified V4-32 vertex and reset.
Tests cover both channels, all supported tested formats, NUM=0, masks,
skip/fill cycles, destination boundary behavior and following MARK commands.
They compare full VU RAM and ROW effects for split vs contiguous streams.

All 15 native CTest regressions pass locally, including compressed colors,
GIF IMAGE2, SDK clear packets, guest checkpoint returns and diagnostic
passthrough. All 47 Python tests pass. A clean pinned source copy accepts
the full patch chain twice with identical resulting diffs. Both canonical
Python and PowerShell patch lists include the new patches; the PowerShell
ROW/COL replacement boundaries were shortened to allow the continuation
reset additions. The CI workflow builds both new tests on Linux and Windows.

The completed preceding 620-second diagnostic is recorded separately in
`frame_state_2026-10-03.md`. It observed 16,013 reserved VU1 lower instructions
with value 0xFFFFFFFB and no numeric-display observer call. These transport
fixes are plausible contributors to corrupt VU code/data, but the retained
retail log does not establish causation. No new retail game test is being
started during this preparation. A playable race, correct native geometry,
Windows retail boot and game FPS remain unverified.

The optimized executable preparation and CI outcomes are appended once
available. The next visual test should use that retained executable identity
and capture the first invalid VU instruction pair with its code-upload origin.

## Prepared Release build

The Linux x64 Release runner linked with FFmpeg enabled, 44622368
bytes, SHA-256 `df7b263d1168f127875c4d6e3ceff75de16fed8413d3177aa9bd95c4ea40603a`.
Its source identities and patch checksums are retained with the receipt.
The final native fixtures were rebuilt and all 15 tests passed, including
a stricter MPG check that every partial code write advances cache generation.
This executable has not been run against the retail game.

## CI validation

For production patch commit `61b2e85cfef2dabbe445231feefe070be75d62d9`,
all four source workflows passed: recovery 37094022162, production GS
37094022251, COP0 37094022256, and VIF 37094022288. The VIF workflow passed
on both Linux and Windows, including the two new production-runtime fixtures.
The subsequent checkpoint strengthens the MPG fixture cache-generation
assertions and retains the prepared Release receipt; production patches are unchanged.
