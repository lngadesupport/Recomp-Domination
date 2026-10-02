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
The isolated FFmpeg-enabled Release trace runner links successfully:
44,621,456 bytes, SHA-256
`66e4e2d96f064af8502a5b9eba1a70323eca93453cf0042ceff7131a6f0ebf37`.
Its 30.046-second native probe observes guest execution and verifies unchanged
binary identity. This short diagnostic overlaps the final navigation run;
no comparable host-performance measurement is claimed.

The native trace contains tag-limit failures at source qword 108, offset 0,
with words `0x43aa148fc3996ea7` and `0x00000000c3996ea7`, requesting 1,812,944
bytes. Another sample at the same source has `0x7f7fffff44fea2f2` and
`0xffffffff3f800000`, requesting 143,152 bytes. These bit patterns suggest
vertex/float-like data being interpreted as GIFtag fields. That is an
inference, not proof of the intended guest data layout or a diagnosed VI/LSU
bug. A separate source-qword 856 sample reaches tag offset 65,296 before
rejecting another 65,296-byte tag, showing assembly past multiple wraps of
16-KiB VU memory. The evidence warrants investigating source pointers, tag
construction and VU writes before merely expanding the packet buffer.

All four workflows pass for source commit
`0f7d9a96745bac7752450c9801cd8f368d546fab`: production GS 37077133776,
recovery 37077133772, COP0 37077133731 and VIF/SDK/guest/IMAGE2/error selectors
37077133830, including Linux and Windows component jobs. All 42 Python tests
continue to pass. A playable race, correct colors, game FPS and Windows
retail boot remain unverified.
