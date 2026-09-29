# Windows x64 build pipeline

This repository does not contain the retail game executable. The build expects the legally owned SCUS_971.77 outside Git.

## Recommended layout

    D:\Recomp Domination\
    |-- SCUS_971.77
    +-- Recomp-Domination\
        +-- BUILD_DOWNHILL.cmd

If the repository is elsewhere, pass the game directory explicitly:

    BUILD_DOWNHILL.cmd "D:\Recomp Domination"

## Prerequisites

- Windows 10/11 x64
- Git
- CMake 3.21 or newer
- Visual Studio 2022 or Build Tools 2022 with Desktop development with C++
- Internet access for the first dependency fetch

## Pipeline

BUILD_DOWNHILL.cmd invokes scripts/build_downhill.ps1, which:

1. Re-validates the exact SCUS_971.77 identity and known instruction anchors.
2. Clones ran-j/PS2Recomp into third_party/PS2Recomp.
3. Pins PS2Recomp to commit 75d729ce40d7eed9649fd4bb05628dee520f3d0c.
4. Builds ps2_analyzer and ps2_recomp.
5. Runs ps2_analyzer on the retail ELF.
6. Preserves the analyzer-generated MMIO, jump table, SCE symbol and patch information.
7. Forces the validated Downhill entry addresses and exact SDK handler bindings.
8. Generates a single combined C++ recompilation unit into ps2xRuntime/src/runner.
9. Copies the generated declaration headers into ps2xRuntime/include.
10. Adds the Downhill game override.
11. Builds ps2EntryRunner.exe for Windows x64.
12. Stages the runnable result under the game directory in DownhillRecompiled.

## Validated guest addresses

- ELF entry: 0x0010A008
- main candidate: 0x001FB6C0
- scePadRead: 0x00254050
- sceSifSendCmd: 0x0025C440

The last two are configured as exact stub selectors and explicit entry-point hints. They are also rebound by the game override at runtime. This is deliberate: the analyzer normally discovers both through real JAL callsites, while the explicit entry hints keep their exact PCs represented in the generated function table if heuristic slicing changes.

## Ghidra

For the authoritative function-boundary pass, export PS2Recomp's Ghidra function CSV and place it at:

    analysis\SCUS_971.77.functions.csv

The build script detects this automatically and sets general.ghidra_output. Until that file exists, the first bring-up uses ps2_analyzer discovery.

## Initial host features

The first bootstrap intentionally sets:

- FFmpeg OFF
- debug UI OFF
- runtime logs ON
- aggressive function logs ON
- IOP/RPC trace ON

This reduces unrelated host dependencies while maximizing boot diagnostics. FMV support and the richer debug UI can be re-enabled after the first stable boot path.

## Output

On a successful build:

    D:\Recomp Domination\DownhillRecompiled\
    |-- ps2EntryRunner.exe
    +-- RUN_DOWNHILL.cmd

Build transcripts are written to the repository's logs directory. Generated configuration and local identity reports are ignored by Git.

## Build hardening and diagnostics

The local bootstrap calculates the same IEEE CRC32 algorithm used by the pinned runtime and rewrites the Downhill override before compilation, so a runner built for one validated SCUS_971.77 does not silently apply the game override to another build.

The runtime build also disables runner unity mode, enables strict return diagnostics and adds MSVC /bigobj to reduce failure risk when the retail game produces a very large generated translation unit.

Before compilation, the script detects whether the game directory contains an extracted disc root (SYSTEM.CNF) or a local ISO. The game override also performs a one-level SYSTEM.CNF search and local ISO discovery at runtime. An ELF-only directory is allowed for compilation but emits a warning because later file/CD access can fail.

After a local build, RUN_DOWNHILL.cmd produces:

    first_boot_latest.log
    first_boot_exit_code.txt
    first_boot_triage.json

To collect the safe non-game diagnostics into one ZIP, run:

    COLLECT_DIAGNOSTICS.cmd

The diagnostic ZIP intentionally excludes SCUS_971.77, ISO/BIN/CHD archives and game assets.

## Recommended first boot workflow

After a successful build, start with the bounded diagnostic probe:

    D:\Recomp Domination\DownhillRecompiled\RUN_PROBE_90S.cmd

This runs the native runner for at most 90 seconds, captures stdout/stderr, then automatically writes:

- first_boot_probe_latest.log
- first_boot_probe.json
- first_boot_probe_triage.json
- first_boot_probe_suggestions.json

If the probe shows useful progress or reaches the menu, use RUN_DOWNHILL.cmd for an unrestricted interactive run.

To package only non-proprietary diagnostics for review, run:

    COLLECT_DIAGNOSTICS.cmd

The diagnostics ZIP deliberately excludes SCUS_971.77, ISO/BIN/CHD/RAR files and extracted proprietary game data.
