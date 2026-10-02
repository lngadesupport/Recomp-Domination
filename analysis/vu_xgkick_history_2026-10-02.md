# VU XGKICK instruction and store history — 2026-10-02

The prior native trace found vertex-like words in rejected GIFtags, but did
not identify the writes or VI values that preceded them. The new opt-in
history records 64 issued instruction pairs and 32 recent store records,
including separate issue and commit phases. Each instruction record includes
its PC, cycle, lower/upper words and all 16 VI values before issue. Store
records include cycle, PC, address, lane mask and words. These are bounded
recent observations, not a complete execution trace.

Enable `PS2_TRACE_VU_XGKICK_ERRORS=1` and
`PS2_TRACE_VU_XGKICK_HISTORY=1`. The source-qword filter defaults to 108;
`PS2_TRACE_VU_XGKICK_SOURCE_QW` accepts 0 through 1023, while malformed and
out-of-range values disable the additional history. Emission is attached to
the existing sampled packet-limit diagnostic, filtered by source qword and
further bounded to four initial histories and powers of two. Records are
thread-local, associated with the executing interpreter, and collected on
that execution thread. The renderer and packet rejection behavior are
unchanged. The issue-store record reflects a store request; commit records
identify writes that became visible to VU memory.

The normal 12 IMAGE/IMAGE2 cases pass with history disabled. A synthetic
oversized packet records the actual issued XGKICK at PC 0, lower word
`0x800006fc`, before the packet-limit rejection. A malformed source selector
emits no history. Those cases are included in the production runtime fixture
CI. All 42 Python tests pass. Fresh and repeated pinned patch application
succeed; the resulting clean runtime diff has SHA-256
`f2bbff8f585b2a5bff28f30b080b06f695c69caba28667392bf13f0b8ffe6964`.
The isolated native history runner is being linked. A separate 620-second
navigation probe uses the previously verified immutable IMAGE2 runner and
adds confirmations after Select Level; it is still running.

No new root cause, playable race, correct colors, game FPS or Windows retail
boot is established by the diagnostic instrumentation alone.
