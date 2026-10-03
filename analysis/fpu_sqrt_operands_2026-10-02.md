# R5900 SQRT/RSQRT operands — 2026-10-02

The production generator selected Fs for SQRT.S. R5900 selects Ft.
For RSQRT.S it emitted 1/sqrt(Fs), whereas R5900 computes Fs/sqrt(Ft).
The pinned upstream interpreter in PCSX2 agrees with these operand semantics:
https://github.com/PCSX2/pcsx2/blob/master/pcsx2/FPU.cpp

The retail instruction 0x46040104 at guest PC 0x177dd4 should compute
f4=sqrt(f4); the old output instead computed f4=sqrt(f0).
This is inside the routine whose return at 0x177efc failed after track
confirmation. That routine also formats a number into its stack frame;
the overwritten return 0x30303030 resembles ASCII zeros. The relationship
between the wrong root operand and that overwritten return is a hypothesis,
not yet established by a before/after native test.

The fixture uses the production decoder and code generator, then compiles
and executes the generated functions. Before the fix, the exact retail
instruction fails: f4=4 and f0=121 produce 11 instead of 2. After the fix,
60 cases pass, covering the retail instruction, distinct Fs/Ft, non-unit
numerators, and destination aliasing each source. All four generator CTest
cases pass under ASan/UBSan, including the exhaustive COP0 regression.
Fresh and repeated complete pinned patch application succeed.
Linux and Windows CI now build this generated FPU regression.

The patch corrects operand selection and the numerator expression. It does
not certify PS2 FPU denormal, negative-root, exception flag, saturation or
rounding behavior. Native C++ was regenerated with the corrected
production generator; Release compilation and the 620-second comparison
completed. Correct image, gameplay and FPS remain unverified.

## Controlled retail routine execution

An isolated test executes the generated retail numeric routine, its guest
float-to-double conversion, and guest formatting callees against the retail
ELF data, using the production runtime and dispatch. Eight independent
float-to-double inputs, including NaN and infinity, convert correctly.
The formatter writes three characters for 0, 2 and 99, but reports 163 for
NaN/infinity and writes ASCII zeros across the saved-register area.

With a controlled vector (3,-4,0), the old emitted SQRT statement is restored
in an otherwise identical copy of the corrected generated function. That
variant produces NaN, returns to PC 0x30303030, and restores s0/s1/RA as
0x3030303030303030. The corrected variant computes root 5, formats ` 3 `,
returns to 0x123456, and preserves SP/s0/s1/RA. This establishes the corruption
chain in the isolated routine; the scheduled full navigation comparison is
still needed to establish how far the game progresses with the fix.
The controlled old variant is not a complete second native build.
`scripts/probe_guest_numeric_chain.py` regenerates this isolated probe from
user-supplied generated code, ELF, runtime archive and fixture linker argv.
No retail code or assets are distributed with the probe template.

Release runner SHA-256:
`2d44da7383fba3bc7a62b5fbd2583d1cbc395d1eb6a4337a0a9abb46dff1a867`.
All four source CI workflows passed for commit 25261b9, including Linux and
Windows generated FPU/COP0 execution and VU/GS/runtime synthetic regressions.
The immutable 620-second navigation comparison completed. Runner identity
matched before and after. It recorded no return to 0x30303030; final EE
snapshots show thread 1 Ready (status 1), PC/RA 0x238c50, rather than Dormant
at the corrupted address. Captures still show black output or incomplete
menu geometry. The scheduled inputs were the same as the previous probe,
but equal input times do not certify equal menu/track execution coverage.
Thus the isolated routine test proves the correction; the native probe
shows no recurrence in this bounded run, not a verified playable race.
All 42 Python tests also pass. Complete native logs and captures accompany
the binary checkpoint; selected records and identities are stored here.
