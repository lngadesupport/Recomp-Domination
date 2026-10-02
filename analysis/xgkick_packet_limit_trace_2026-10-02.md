# XGKICK packet-limit diagnostics — 2026-10-02

The IMAGE2-enabled navigation reaches the inventory but continues to report
XGKICK packet-limit errors. These errors are not diagnosed as malformed guest
instructions or palette failures.

`ps2recomp-vu-xgkick-error-trace.patch` adds opt-in diagnostics on the existing
VU execution thread. With `PS2_TRACE_VU_XGKICK_ERRORS=1`, it records the rejection
reason, cycle, PC, source qword, tag offset, copied bytes, both GIFtag words,
raw NLOOP/FLG/NREG fields, requested bytes and the existing 65,536-byte limit.
Raw NREG 0 denotes 16 registers. It emits the first 32 samples and subsequent
powers of two. Disabled and malformed selectors emit no additional diagnostic.
The packet limit and rejection behavior are unchanged.

A synthetic oversized PACKED tag at VU qword 0, NLOOP 4096 and raw NREG 0,
requests 1,048,592 bytes and remains rejected. Its opt-in trace matches those
fields. The normal 12 IMAGE/IMAGE2 cases still pass, as do enabled, disabled
and malformed diagnostic cases. Linux/Windows CI includes the three selector
cases. Fresh and repeated patch-chain application succeed with clean diff
SHA-256 `f2d3e019a813b9566ccb610a1c0c7129510307da936ab2954550f2a3219dd835`.
A separate native trace runner is being linked; no retail packet provenance
conclusion is claimed yet.
