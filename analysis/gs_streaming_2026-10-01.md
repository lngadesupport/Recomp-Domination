# Production renderer: image streaming and palette diagnostics

## Corrected defect

`GSCpuBackend::UploadImage` discarded incomplete 24-bit pixels at the end of a call. Sending a 22-pixel image in 16-byte blocks failed at pixel 5: actual `aa076024`, expected `aa602406`. The same image supplied contiguously has a different byte grouping. The additive `gs-upload24-continuation` patch retains up to two trailing bytes and completes the pixel on the next call. Both color and depth 24-bit transfers use this carry; transfer start and runtime reset discard abandoned carry.

The public API regression checks 168 scenarios: chunks from 1 to 80 bytes for CT24/Z24, preservation of the existing upper byte, row/page crossing, completion, padding, cancellation, reset, and empty calls. It passed against the full built runtime. The original runtime fails the 16-byte case. The companion CLUT regression now covers 20 combinations of indexed format, palette format and storage mode, checking forced reload and CLD=0 retention.

A separate CMake target compiles the actual production `gs_cpu_backend.cpp` and `ps2_gs_memory.cpp`, not a mock or copied algorithm. It needs no retail game source, graphics window or multimedia libraries. Linux AddressSanitizer/UndefinedBehaviorSanitizer instrument the renderer and both fixtures. The new GitHub workflow runs the same production fixtures on Linux and Windows.

```sh
cmake -S tests/gs-renderer -B build/gs-tests \
  -DPS2RECOMP_SOURCE=/absolute/path/to/patched/PS2Recomp \
  -DGS_TEST_SANITIZE=ON
cmake --build build/gs-tests --parallel 2
ctest --test-dir build/gs-tests --output-on-failure
```

Both additive patches and the complete pinned patch series passed initial application and reapplication.

## Native game observations and limitations

The 90-second upload diagnostic used runner SHA256 `f8662ffcd1c6c787b6a47ecb9c86ad275f3e9ef1e0d420ba1d40115ea785c731`, with unchanged executable identity. It reached 122 bounded sprite records. The 40-second capture remained corrupted; the 80-second capture was black. No 24-bit uploads were logged. Therefore this reproducible component defect is not established as the cause of the game's current corruption.

An additional 90-second palette diagnostic used unchanged runner SHA256 `de5f83eed0d3210af9b1d486b83da1cbab77f1155702438e994f698ab32efa56`. It logged palette loads at CBP=6753 with sampled zero entries but did not reach textured sprite callbacks. It cannot establish whether the later font palette is correct. Native bring-up timing/progress still varies across probes.

`PS2_TRACE_GS_IMAGE_TRANSFERS=1` enables bounded transfer and 24-bit upload records; `PS2_TRACE_GS_CLUT_LOADS=1` enables bounded existing palette load/sample records. Both are off by default. These diagnostics introduce no extra VRAM reads or rendering changes, though tracing can affect timing. Native runs terminate at the requested deadline with SIGKILL; this is not an observed crash.

Evidence is in `analysis/evidence/2026-10-01-gs-streaming/`. No playable menu, race, 60 FPS, 75 FPS, or Windows retail execution is validated. Host presentation frequency remains separate from measured game performance.

## Final source validation

Commit `37d6af1764a3ac44c5d2281992aae8b6dfb027d1` passed the production GS workflow on both Ubuntu and Windows, run `36938269850`. Linux instruments the actual renderer with ASan/UBSan. Each platform builds and executes both fixtures. This validates component behavior and Windows compilation, not retail gameplay.

The final 90-second native probe used runner SHA256 `af0e1c144d126f6fee06d81d4697b545f94ec07929dc94e98684972181889d51`, with unchanged executable identity. It again did not reach textured sprites or nonzero palette texel records; it supplies no further evidence about the post-intro font palette. Evidence is in the `final/` subdirectory.

All three workflows for source commit `37d6af1764a3ac44c5d2281992aae8b6dfb027d1` completed successfully: production renderer (`36938269850`), COP0 DMA condition (`36938269784`), and runtime recovery (`36938269840`). All 29 local Python regressions also passed. The private Linux diagnostic checkpoint contains the final native runner hash listed above; game assets are excluded.
