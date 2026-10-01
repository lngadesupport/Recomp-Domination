# VIF1 queue diagnosis — 2026-10-01

Source checkpoint: `986bfd16464c7c2d36c003fb804c52badc4f97ea`.
Runtime upstream pin: `75d729ce40d7eed9649fd4bb05628dee520f3d0c`.

The previous native probe reaches guest wait `0x1B4648` with return address
`0x1EBEEC`. This loop ORs queue flags at `0x29E1C8`, `0x29E1CC`, and
`0x29E1E4` until all are zero. Guest function `0x21EA60` registers VIF1
handler `0x21EAA0` for DMAC cause 1. The handler conditionally calls
`0x21E9A8`, which starts the next VIF1 chain and clears these flags.

`PS2_TRACE_DMAC_IRQ=1` now observes registrations, cause masks, completions,
and the guest wait without changing delivery. The guest adapter samples CHCR,
QWC, TADR, D_STAT, flags and COP0 status on the EE executor. Repeated wait and
completion output is bounded to initial calls and powers of two. Default-off.
Both POSIX and Windows patch workflows include the same version-pinned patch.

## Verification

- Fresh disc staging: 2,335 files, 2,520,670,702 bytes, checked against archive CRCs.
- Reconstructed diagnostic ISO: 2,525,089,792 bytes; original DVD layout not asserted.
- 11 Python tests passed.
- C++20/AVX2 override syntax check passed.
- New patch applied twice to a clean pinned upstream checkout.
- 85 native memory/DMA and scheduler tests passed, zero failures.
- GitHub Actions run 36864063291: Ubuntu and Windows jobs passed. Windows
  checks cover patch application and isolated MSVC compilation, not a full
  Windows retail boot.

This instrumentation alone does not establish the root cause. No playable
menu, race, or 120 FPS validation is claimed.

## Native retail probe (240 seconds)

Runner SHA256: `12cf88545ee229741ad64e920a36255b604746f29029668976ad13d50251aff6`,
unchanged for the entire probe. The timeout was imposed by the probe harness;
SIGKILL at the bound is not evidence of a crash.

The last guest wait sample has PC `0x1B4648`, RA `0x1EBEEC`, flags `0,3,1`,
CHCR `0x70000045` (STR clear), QWC 0, TADR `0x6202C0`, D_STAT 7 and
COP0 status `0x10001`. Cause-1 completion samples after startup report
`enabled=0`, with one registered DMAC handler. The screenshot remains corrupted,
without a usable menu. This narrows the issue to queue/interrupt timing; it
does not establish that changing the renderer would unblock the guest.

Build provenance limitation: the scheduler compiler had already read its source
before registration/mask-transition logging was added. This runner contains the
completion and wait probes, but not those two additional log types. Their source
is committed and passes CI; a future native build must force scheduler
recompilation before claiming those transitions were observed.

The separate interrupt suite also passed all 10 tests (95 native tests total
across the three relevant suites). Evidence: `evidence/2026-10-01-vif1-queue/`.
No interrupt-delivery workaround or renderer API change was made.
