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
rounding behavior. Native C++ has been regenerated with the corrected
production generator; Release compilation and post-track comparison are
pending. Correct image, gameplay and FPS remain unverified.
