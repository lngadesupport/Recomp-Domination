# Texture investigation after introduction

Added opt-in `PS2_TRACE_GS_TEXTURES`: bounded sprite records contain coordinates after XYOFFSET, framebuffer/texture pointers, texture format and CLUT settings. Texel records capture raw indices from the existing texture read, without additional memory reads or altered rasterization.

The initial 60-second and 120-second probes of hash `b3ce694ae7c61803da709e22ff17214a1f48738adf69ea15b0cb3b8cdba1bb60` did not reach these draw callbacks. Therefore the earlier automatic introduction skip result was not reliable across these runs. The Start window was previously consumed by the first movie. A new patch resets it at MPEG CD stream start; the diagnostic option can also request skipping later movie streams when left enabled.

A subsequent 90-second probe with the reset patch reached the graphics callbacks. Executable hash `ffea3f08b55d3d7099c3cc80b4eaf85b11f017cb97bb41c107adaedcbd18eb28` was stable before/after, and termination was the intended deadline. This is evidence of progress, not proof of reliable skipping under all timings.

Example: XYOFFSET=(1728,1936), sprite rectangle=(202,199)-(227,209), framebuffer=140, texture=128, texture PSM=36, CLUT=6805. The rectangle is inside the visible 640x224 area. Later texture samples include PSM=19, TBP=7936, UV=(1,15), raw index=57. Other sampled indices are zero; zero can be valid transparent texture content.

These observations reduce the plausibility of simple offscreen placement for the sampled sprites and of all texture data being zero. They do not establish texture addressing or CLUT correctness. The 40-second capture remains corrupted. Menu, racing and 60/75 FPS are unverified. Next investigation: indexed texture addressing, CLUT loading and draw tests/composition, using captured guest state rather than speculative framebuffer forcing.

Both patches applied successfully to a pinned verification worktree twice. The updated native runner linked with FFmpeg enabled. The million-timestamp intro test passed ASan/UBSan and all 29 Python regressions passed. No new Windows retail boot is claimed.
