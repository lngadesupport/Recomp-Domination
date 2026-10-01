# CLUT reload regression — 2026-10-01

Fixed a reproducible palette reload defect in the production CPU GS backend. LoadClut(CLD=1) previously read the palette through TexturePageCache; a second load at the same palette base could return stale colors after VRAM was updated. The new additive patch reads palette entries directly from VRAM. Texture sampling cache behavior remains unchanged.

The regression uses public GSCpuBackend APIs: load a green palette, update that entry to red, force a second CLD=1 load, submit a textured sprite, and read the framebuffer pixel. The original production backend produces `8000ff00` and fails; the corrected production backend produces `800000ff` and passes. The original implementation was compiled separately with production compile flags and linked ahead of the same runtime archive, without mutating the running game binary.

Reproduce on Linux after building the runtime:

```sh
python scripts/test_gs_clut_reload.py third_party/build-intro-runtime
```

The test requires a built production runtime, GNU-style generated link.txt, and C++20 compiler; it is not a self-contained Windows test or a mock implementation. The complete pinned patch series was applied to a fresh temporary upstream checkout and then applied again successfully.

A 90-second native game probe used runner SHA256 `c75281ac8389c6978e9105d0827e15f5194b372e561b1e103d370916a5e73983`, with automatic intro skipping enabled. The runner identity stayed unchanged during the probe. Termination was the intentional time limit (SIGKILL), not an observed crash. Post-intro graphics still show corrupt patches on a black background: this component correction does not establish that it caused or resolved the game's visual corruption. No playable menu, race, stable 60 FPS, or 75 FPS result is validated.

Evidence: `analysis/evidence/2026-10-01-clut-reload/`. This commit stores source, regression and bounded diagnostic records; retail ELF/assets and generated game source are excluded.
