# Executor frame-state observation — 2026-10-03 UTC

The corrected FPU runner completed its prior 620-second probe without a
0x30303030 return, but equal timed inputs did not establish equal menu/track
coverage. Guest 0x238C50 is an interior continuation of the frame/VSync wait
at 0x238C00; its PC alone cannot identify the active game mode or a stall.

The new opt-in `PS2_TRACE_DOWNHILL_FRAME_STATE=1` observers record the saved
caller, stack words, GPR values, VSync tick and numeric-display call count.
They wrap entry plus all generated wait continuations (0x238C50/64/70), and
the numeric-display routine 0x177DA0 plus 0x177E68/78. Values are read on the
guest executor thread. Each wrapper invokes the original generated function
once; it changes no guest instructions, RAM or synchronization rules.
Wait output is bounded to four initial calls and every 120th call through
61440 (516 records maximum). Numeric output uses the existing first-16,
powers-of-two and bounded anomaly rule. Calls count wrapper invocations,
including resumes, rather than game frames or FPS.

The production wrapper fixture passes 27 passthrough cases: four wait
entry/resume PCs at six sampling/cap boundaries and three numeric entry/
resume PCs. It compares the entire R5900 context and RAM against a direct
call of the same test function. The fixture is included in Linux/Windows CI.
The instrumented Release runner linked (SHA-256
`bb294d02a70f89dc3d15d120e1f67fc9a51459c72659d64103414e9c3c42578b`).
Both source workflows for a879505 passed, including the observer fixture on
Linux and Windows. A 620-second navigation probe started and its early
samples show callers 0x1b5344 and 0x1ec350 with numeric_calls=0.
The transient workspace was reset before its final result was preserved;
there is no retained full log or final completion receipt for this run.
Early values are recovered from the session tool output and labeled as such.
The probe must be rerun before assessing late navigation coverage.

The new parser groups sampled callers and reports numeric-routine coverage.
Its five tests cover empty, valid, truncated, invalid/negative and numeric
records after wait sampling stops. All 47 Python tests pass after recovery.
No playable race, correct image, native mode coverage or game FPS is yet
certified by this observer.

## Completed recovery rerun

The rebuilt instrumented Linux Release runner (`33302a42de77f9b1afe169c0656f96305cde34e8658cdbc0d3b4dbbe9183eb96`,
44622128 bytes, FFmpeg enabled) ran for 620.058 seconds.
The bounded probe ended at its timeout, and runner identity matched before
and after execution. All 13 requested key events were recorded.
The controller fix separates metadata from the progression output directory;
its recovery CI run 37092923928 passed.

The complete log contains 14 valid frame-state samples,
0 malformed samples and 0 numeric-return records.
Observed callers: `{"0x1b5344": 2, "0x1ebf6c": 1, "0x1ec350": 11}`.
Maximum sampled numeric wrapper count: 0.
The final sampled invocation is call 1440,
VSync tick 892; no further sampled wait-return records
were emitted. This does not identify the active mode or prove a scheduler deadlock.
There was no observed 0x30303030 return in this rerun, but the numerical
HUD routine was not exercised by its observer; this is not native HUD validation.

There are 16013 reserved VU1 lower-instruction records:
`{"0xfffffffb": 16013}`. Captures show black
frames and corrupted isolated geometry; no playable race is established.
Host refresh counters are not game FPS. This run omitted the earlier
triangle/palette trace filters and is not a controlled FPU A/B comparison.

The next discriminating graphics investigation is to capture the complete
upper/lower instruction pair at the first reserved VU1 issue and its last
code upload (MPG or direct VU code write), including source/destination bytes
and code generation. Repeated 0xFFFFFFFB alone does not distinguish a bad
upload, wrong microprogram control flow, or incorrect instruction decoding.

Completed receipts, selected log, inputs and capture hashes are under
`analysis/evidence/2026-10-03-frame-state/completed-*`. Full runtime log and
captures are retained with the diagnostic executable package.
