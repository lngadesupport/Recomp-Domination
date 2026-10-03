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
Native linking and an instrumented navigation probe are pending.
No playable race, correct image, native mode coverage or game FPS is yet
certified by this observer.
