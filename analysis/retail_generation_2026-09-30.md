# Retail generation checkpoint — 2026-09-30

Actual local run using the user-provided `SCUS_971.77`, not a synthetic fixture.
Project baseline: `6f93644`; PS2Recomp: `75d729ce40d7eed9649fd4bb05628dee520f3d0c`.
ELF SHA-256: `adfda7b73a8f05fb20a3f0f318772e9d3797fd4d6c0a6c0078ae392df0f0cf0c`.

## Observed results

| Stage | Result |
| --- | --- |
| Build pinned analyzer/recompiler | Passed, GNU C++ 13.3.0, Linux x64 |
| Analyze retail ELF | Exit 0; 5,527 functions, 32 sections, no symbols or relocations |
| Recompile retail ELF | Exit 0; 5,415 guest functions, 112 stubs, no skipped functions |
| Generated output | 5,528 C++ files, 82,137,805 bytes |
| Decode failures / unhandled instructions / generator errors | 0 / 0 / 0 |
| Critical guest fallback failures | 0 |
| Required entry, main, PAD and SIF entries | All present in registration table |
| Confirmed PAD/SIF wrapper calls | `ps2_stubs::scePadRead`, `ps2_syscalls::sceSifSendCmd` |
| C++ syntax check | All 5,528 files passed, grouped into 56 translation units, GCC C++20 / AVX2 |
| Windows retail link / first boot / menu / race | Not executed |

No Ghidra map was used. The analyzer fallback discovered one jump table and
376 SCE SDK matches (342 renames, 34 additions). There were no analyzer patches.
The runtime stub filter preserved incomplete handlers as guest implementations.

The generator reported 532 warnings, 530 indirect-control-flow fallback
promotions (64,184 fallback entries), and 51,430 additional entrypoints.
These are compiler-generated fallback entries; the bring-up automation did not
accept any new log-derived entrypoints during this run.

Two binding collisions were observed: `memcpy` versus confirmed `scePadRead`
at `0x00254050`, and `_sceSifSendCmd` versus confirmed `sceSifSendCmd` at
`0x0025C440`. The resulting wrappers were inspected and the confirmed handlers
won in this run. The headless command verifies their actual emitted calls.
Other analyzer classifications still require runtime evidence; this check does
not establish that every SCE match is semantically correct.

## Reproduce generation

Python 3.11+ is required. Build the pinned analyzer and recompiler first. Then:

```bash
python3 scripts/recompile_downhill_headless.py \
  --elf /path/to/SCUS_971.77 \
  --source third_party/PS2Recomp \
  --analyzer /path/to/ps2_analyzer \
  --recompiler /path/to/ps2_recomp \
  --work analysis/local/retail-headless
```

This command generates multi-file C++ with the conservative patch policy,
filters TODO/missing host handlers using the bootstrap's source scan policy,
and checks registration entries and confirmed wrapper calls. It does not
stage generated files into the runtime, build a runner, or execute the game.
Its timeout is per analyzer/recompiler stage. Logs and machine-local paths
remain under ignored `analysis/local`.

The syntax check used only generated output and pinned runtime/IOP headers;
it did not link runtime implementations. The existing Windows command remains
the next integration step: `FULL_PIPELINE_DOWNHILL.cmd`. A successful retail
generation and GCC syntax check do not establish a successful MSVC link,
first frame, or playable game.

No retail ELF, generated retail C++, or game assets are committed.
