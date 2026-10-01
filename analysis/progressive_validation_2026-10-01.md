# Progressive validation — 2026-10-01

The current performance goal is **60 stable FPS**, with **75 FPS as a stretch goal**.
The policy is executable configuration, not a measured gameplay result.

## Implemented

- Sequential, bounded regression/build/native-batch pipeline; each batch must
  return the expected seed, case range, level, family counts and executable hash.
- Default native progression: 1,000 + 9,000 + 90,000 cases. The cap is configurable
  up to 10 million; increasing it does not create new gameplay coverage.
- Reproducible handler/ISO fixtures exercise the actual inline production helpers.
  The native harness checks its fixtures against independently constructed expected
  results. It does not execute the full runtime, DMA/VIF/GS, or retail gameplay.
- Fresh retail probe support for configured runner/ELF/disc paths; isolated copies,
  bounded logs/process lifetime, runner/ELF identity, explicit experimental flags.
- Historical-probe classification is marked separately from fresh execution.
- Sampled VIF1 queue observations gate menu/race/performance stages; no generic
  log marker or host frequency approves a playable menu or FPS.
- Per-scenario frame-time evaluator checks unique, ordered frames, dropped-frame
  IDs, minimum 60-second duration and every 60/75 FPS interval. Its regression
  inputs are synthetic and establish evaluator behavior, not game performance.
- Ubuntu/Windows CI now executes 100,000 native cases automatically on bringup
  source changes. Same IDs/seeds across platforms are not counted as new cases.

## Local evidence

Final campaign: **1,000,000 distinct case IDs**, seed 854545 (`0xD0A11`):

| Batch | Case IDs | Passed | ISO cases | Handler cases |
|---|---|---:|---:|---:|
| Initial | 0–999 | 1,000 | 500 | 500 |
| Expanded | 1,000–9,999 | 9,000 | 4,500 | 4,500 |
| Stress | 10,000–999,999 | 990,000 | 495,000 | 495,000 |
| Total | 0–999,999 | 1,000,000 | 500,000 | 500,000 |

ASan/UBSan reported no failures. Leak detection was disabled because the managed
runtime does not expose the task enumeration required by LSan; leak coverage is
not claimed. There are 12 ISO fixture classes and 3 handler modes, not one million
independent functions/test definitions. Earlier same-seed reruns are not added
to the distinct count. The final run also passed **29 Python regression tests**.

Two isolated, deliberately broken copies validated test sensitivity:

- Removing the leaf continuation fails case 0 before the host handler can proceed.
- Accepting an unsupported extended-attribute record fails ISO case 19.

A full pipeline run with the first mutation stopped at `generated-smoke`, returned
failure and never started `generated-expanded`. This experiment also exposed a
relative custom-compiler path issue; the runner now resolves compiler paths
before switching its working directory. The production helpers were unchanged.

## Gameplay result

No fresh retail boot was executed in this campaign. The immutable prior
240-second capture was reclassified as historical evidence. It contains 24 wait
samples and 65 IRQ samples; the final queue flags are `0,3,1`, PC `0x1B4648`,
VIF1 STR clear and QWC zero, with masked completions observed earlier.

The complete pipeline correctly returns **blocked (exit 2)** at the menu gate.
Component-only validation can return success separately. Menus, races, 60 FPS and
75 FPS remain unverified. The sampled evidence does not establish the complete
root cause or the duration of a stall.

Evidence directory: `evidence/2026-10-01-progressive-tests/`.
Commands and limitations: `../docs/PROGRESSIVE_TESTS.md`.

## Continuous integration

Source commit `06680c4556ecdf216b41299dc2816010522383ee`: GitHub Actions run
36886047360 passed on Ubuntu and Windows. Each platform ran 100,000 native
cases and the 29 Python regressions. Ubuntu used ASan/UBSan; Windows used
MSVC. These are additional executions of existing same-seed case IDs, not
200,000 new distinct cases. CI does not execute a retail boot.
