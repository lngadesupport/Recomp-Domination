# First native retail boot — 2026-09-30

The actual `SCUS_971.77` was linked into a Linux x64 diagnostic runner and
executed with the real pinned runtime. This is a native recompilation probe,
not a Windows test and not a verified playable build.

## Evidence

| Stage | Observed result |
| --- | --- |
| Retail generation | 5,527 functions; 5,415 recompiled, 112 stubs |
| Native runtime and retail link | Passed with GCC 13.3.0, Debug, C++20, AVX2 |
| Graphics host | raylib 5.5, virtual X11 display, software OpenGL |
| Guest ELF loaded | Yes, entry `0x0010A008` |
| Guest main reached | `sub_001FB6C0_0x1fb6c0` entered and returned |
| SIF/IOP reached | `SifInitRpc` and nine IRX open attempts |
| Registered HLE fallbacks | SIO2MAN, MCMAN, MCSERV, PADMAN, LIBSD |
| Module load failures | MTAPMAN, CDVDSTM, 989SND, 989ERR |
| Missing recompiled functions / unsupported instruction markers | None in this capture |
| Probe termination | Watchdog timeout, 15.156 seconds, signal 9 |
| Shared triage result | `iop-module-load`; furthest milestone `sif-iop` |
| Guest graphics / menu / race | Not observed |
| Windows retail link / boot | Not executed |

Runner SHA-256:
`6dbc8994492606a803ff4450bf1019cd3cdf56fc4be19c7607f77cb1b7530a4b`.
Pinned PS2Recomp revision:
`75d729ce40d7eed9649fd4bb05628dee520f3d0c`.
ELF SHA-256:
`adfda7b73a8f05fb20a3f0f318772e9d3797fd4d6c0a6c0078ae392df0f0cf0c`.

The reusable POSIX builder was then executed and linked successfully. A second
guest probe of that rebuilt runner ended at 10.146 seconds with the same
`iop-module-load` classification, five HLE fallbacks and four load failures.
The rebuilt runner was 220,857,368 bytes, SHA-256
`fda1171aea6d18e0d0b1ac94db293d7d8efbe779ffa4eeb6df02d6f0eb11eef8`.

The exact existing Windows compatibility replacements were applied from
`patch_downhill_ps2recomp.ps1`: VIF1 ROW/COL preservation, its regression-test
source changes, and failed guest FileIO logging. The existing Downhill
override was staged with the verified ELF file CRC32 `0x1C6EB372`.
There were no new guest patches, replacement module implementations, or
manually added entrypoints in this probe.

## Current blocker and secondary evidence

The probe had the ELF but no extracted disc or ISO. The first sector request
was unresolved: LBN `0x10`, one sector, guest PC/RA `0x0020E4FC`. Subsequent
module opens used `cdrom0:\MOD\<module>.IRX;1` and failed because the physical
files were unavailable. The registered HLE providers handled five standard
modules; four others could not load. Near the end of the trace, execution
repeatedly entered and returned from `sub_00245AE8_0x245ae8`.

There was also an early `[guest-branch:missing-target]` diagnostic for a return
to address zero, source `0x0025EF70`, policy 1; execution continued afterward.
The `SetupHeap` log showed size `0xFFFFFFFF` and runtime base/end `0x008A0400`.
These remain diagnostic leads, not proven causes of the later wait. The lack
of disc data is sufficient reason to restore the real data before applying
additional guest or runtime fixes.

Attempts to recover all five previously uploaded multipart archives failed
with HTTP 502. A repeat of part 1 also failed. No ISO or assets were installed,
so a probe with real physical IRX files could not be completed in this session.

An earlier host-startup attempt failed to open its virtual display and exited
with signal 11 before loading the ELF. It does not count as a guest boot.
Starting the virtual display and runner within the same execution environment
resolved that host issue. Audio initialization also failed in the container;
the guest probe still reached main and SIF/IOP.

## Repeatable Linux diagnostic path

Python 3.11+, GCC C++20, CMake 3.21+, x64/AVX2 and the raylib X11/OpenGL
development dependencies are required. Use the existing headless generation
command first, then:

```bash
python3 scripts/build_downhill_posix.py \
  --elf /path/to/SCUS_971.77 \
  --source third_party/PS2Recomp \
  --generated analysis/local/retail-headless/output \
  --build third_party/build-retail-linux
```

The builder verifies the ELF, the pinned checkout and the generation report,
stages generated files and the CRC-bound override, applies the canonical
compatibility replacements and builds the real runtime. `--prefix` and
`--raylib-source` allow existing local dependencies; downloads are still
needed when raylib is not available. No system package installation is
performed by this script.

In a Linux desktop session, or under `xvfb-run` where Xvfb is installed:

```bash
xvfb-run -a python3 scripts/probe_downhill_posix.py \
  --runner third_party/build-retail-linux/ps2xRuntime/ps2EntryRunner \
  --elf /path/to/SCUS_971.77 \
  --out analysis/local/probe-next \
  --seconds 30 \
  --pwsh /path/to/pwsh
```

Choose a fresh output directory each time. The probe kills the process group
on timeout or excessive log growth, preserves runtime/function traces and
reuses the existing PowerShell triage and suggestions scripts. Its report
distinguishes native signals from watchdog termination and host initialization
from guest execution. The log-size check is polled, so a large write can exceed
the configured threshold before termination. Four local regression checks
passed: timeout/output retention, real exit code/trace retention, log-limit
termination, and guest-stage/native-signal reporting.

Next run: provide the actual extracted disc root and/or ISO through the
existing `downhill_cd_root.txt` / `downhill_cd_image.txt` sidecars beside the
ELF. On Windows, use `FULL_PIPELINE_DOWNHILL.cmd` with those data available.
Keep automatic entrypoint expansion blocked for this IOP-module classification.

Retail ELF, generated C++, executable, archives, disc contents and raw function
traces remain local and are not committed.
