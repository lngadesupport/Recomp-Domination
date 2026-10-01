# COP0 DMA condition correction — 2026-10-01

The production recompiler emitted `false` for every COP0 conditional branch. Retail function `0x217D88` uses `BC0T` and inverts the result to report whether DMA is busy. Its caller at `0x216160` starts the queued VIF1 chain through `0x21E9A8` only when that function returns zero. The old emission always returns one, regardless of completion status.

`ps2recomp-cop0-dmac-condition.patch` implements BC0F/T/FL/TL using current D_STAT.CIS and D_PCR.CPC. It also applies likely-branch delay-slot annulment. The condition is true when all selected channel completion bits are set; interrupt masks and DMA priority bits are excluded. It is not a test of CHCR alone.

The condition was checked against PCSX2's COP0 and DMAC register definitions at commit `81526d4dc7cc70e4ae75abb35a789417456c6d43`. Sources: [COP0.cpp](https://github.com/PCSX2/pcsx2/blob/81526d4dc7cc70e4ae75abb35a789417456c6d43/pcsx2/COP0.cpp), [Dmac.h](https://github.com/PCSX2/pcsx2/blob/81526d4dc7cc70e4ae75abb35a789417456c6d43/pcsx2/Dmac.h).

## Validation

- 1,048,576 distinct combinations of the ten channel selection/completion bits, including irrelevant high bits.
- 5,242,880 executions of production-generated functions: four branch variants plus the exact seven-word retail predicate. The retail fixture's instruction words were verified against the known ELF hash.
- Real production decoder/emitter and condition helper; the execution harness uses an explicit MMIO/runtime test double. It is not a full runtime or game boot test.
- ASan/UBSan passed. LeakSanitizer disabled for this managed environment.
- Delays execute once for ordinary branches, and only on taken likely branches. Return PC and MMIO reads are checked.
- Restoring constant-false emission fails the regression. Focused reproduction with D_STAT=7 and D_PCR=2: old predicate returns busy=1; corrected predicate returns busy=0.
- All 29 Python regressions passed. Fresh version-pinned patch application and second application passed.
- Verified regeneration of 5,528 retail C++ files; corrected retail predicate also passed syntax checking with actual runtime headers.

## Pipeline diagnosis

`ps2recomp-vif1-command-trace.patch` adds opt-in `PS2_TRACE_VIF1_COMMANDS` diagnostics. It retains the latest 64 parsed VIF1 commands, their byte offsets and packet sizes. At the known queue wait PC `0x1B4648`, the EE checkpoint prints a new history only when the command sequence changes, with VIF/GIF status, VU PC, execution cycles, E-bit completion and D/T halts. Capture and dump occur on the EE thread, not by reading the ring from the presentation thread.

This instrumentation does not alter flush semantics, force interrupts, clear queue flags or report budget exhaustion as normal VU completion. A 100,000-record test verifies history ordering and wraparound. The full native build and controlled probes described below confirm that the COP0 correction clears this wait and expose a separate rendering problem.

Correct pipeline references: DIRECT/DIRECTHL use PATH2; XGKICK uses PATH1; EE GIF DMA uses PATH3. VU E is bit 30 of the upper instruction and has a delay slot. GIFTag EOP is a separate bit. FLUSH=0x11 and FLUSHA=0x13. MPG NUM=0 is 256 64-bit instruction pairs, 2,048 bytes, 128 quadwords.

No playable menu, race or 60/75 FPS claim is established by these component tests.

## Reproduce

Apply `scripts/apply_runtime_bringup_patches.py` to upstream revision `75d729ce40d7eed9649fd4bb05628dee520f3d0c`, then configure its root with:

```sh
cmake -S PS2Recomp -B cop0-build -DCMAKE_BUILD_TYPE=Debug \
  -DPS2X_BUILD_RECOMP=ON -DPS2X_BUILD_RUNTIME=OFF -DPS2X_BUILD_ANALYZER=OFF \
  -DPS2X_BUILD_TEST=OFF -DPS2X_BUILD_STUDIO=OFF \
  -DCMAKE_PROJECT_INCLUDE=/absolute/path/Recomp-Domination/tests/cop0_regression.cmake \
  -DCOP0_TEST_SANITIZE=ON
cmake --build cop0-build --target cop0_generated_execution vif1_command_trace_test --parallel 2
ctest --test-dir cop0-build --output-on-failure
```

On Windows, pass `--config Debug` to the build, `-C Debug` to CTest and disable sanitizers. The dedicated GitHub workflow automates both platforms.

## Native game comparison

The Linux diagnostic runtime was linked with FFmpeg 6.1 decoding enabled (Debug, software desktop rendering). Its isolated executable hash was `3351a709d4d6ef7e332859010ee6a8150c083aa670376faf366d798e4eec061d` before and after the 240-second probe. All 2,335 disc files passed CRC verification; the probe ISO is reconstructed, not an assertion about the original DVD layout.

The corrected build played the introductory video and progressed through subsequent resource loading. All 21 sampled queue returns had zero flags, with the last sampled return at `0x1EBEEC`. A separate 120-second input probe also kept the queue clear. Input injection records mean X11 accepted the scheduled keys; they do not validate a navigable menu.

For a controlled comparison, only the generated condition in retail function `0x217D88` was temporarily replaced by `false`. The runtime, other generated functions, data, options and six scheduled keys were retained. Both variants ran for 120 seconds. The original source was restored and rebuilt; the corrected executable returned to its exact previous hash.

| Observation | Constant-false predicate | Corrected predicate |
| --- | --- | --- |
| Native executable | `c72d67d4996984c6f6ac0252084d882cc46d6f459b50b53fc7b15d0a3daa1a8d` | `3351a709d4d6ef7e332859010ee6a8150c083aa670376faf366d798e4eec061d` |
| Last sampled PC | `0x1B4648`, queue wait | `0x1EBEEC`, returned to caller |
| Queue flags | `0,3,1` | `0,0,0` |
| VIF1 CHCR STR | Clear | Clear |
| Masked completions | Observed | Observed |
| Usable menu or race | Not verified | Not verified |

At the reproduced wait, the opt-in trace reported VIF_STAT=0, GIF_STAT=0, VU PC=`0x1040`, last VU run=582 cycles and `ended_by_e=1`. The latest 64 VIF codes were captured. This provides direct evidence that the observed wait can persist after VU completion because the game's queue-start predicate was wrong. Masked completions alone did not establish the cause.

## Remaining graphics diagnosis

`ps2recomp-gs-pipeline-trace.patch` adds opt-in `PS2_TRACE_GS_PIPELINE=1` snapshots through the GS's locking accessors and atomic DMA/GIF/VIF counters. It records presentation buffers and at most 12 recent draw events per sampled upload. It does not change framebuffer selection or rasterization.

An additional 120-second native probe (hash `f08ef3d9bde49f96e85942f5269650c1632691dbde1c75eecf9ad70e97e687f8`) captured 36 sampled draw events: textured sprites and triangles reach the GS after the introduction. The presented image is still corrupted or empty. Vertex bounds in these logs are raw GS coordinates before XYOFFSET subtraction; their values around 2,048 do not by themselves prove clipping errors. Framebuffer fields are register units, not byte addresses.

The next investigation is texture/CLUT data, draw state and presentation buffer selection after the introduction. No speculative flush or IRQ workaround was introduced.

The COP0 workflow and runtime recovery workflow passed on Linux and Windows at source commit `8f9b342b50277dd8a6d5f7ceed69e93f0b962841`. Windows results are component/patch checks, not a Windows retail game boot. Native probe timeouts deliberately terminated the process; executable identity checks passed. No game-frame telemetry establishes 60 or 75 FPS.
