# Automatic intro skip: native comparison

A Linux Debug runner with FFmpeg 6.1 was rebuilt from verified retail generation (5,528 C++ files). SHA256: `1654c4b60fd99c4dabc67a6a0469dd148d11b864c06e0229e492a8d284238349`. All 2,335 data files passed CRC verification; the ISO is reconstructed, not original-disc-layout validation.

Two bounded 120-second probes used the same executable, ELF and data, changing only `PS2_DOWNHILL_AUTO_SKIP_INTRO` (1 vs 0). No external key input was injected. Executable identity checks passed. Both probes ended by their intended timeout, not an observed crash.

At 10 seconds both variants showed the copyright screen. At 20 seconds the automatic variant had passed the movie and reached the corrupted post-introduction rendering; the baseline still displayed the movie. Twelve bounded guest-pad injection log records were observed in automatic mode, none in baseline. This confirms native advancement past the introduction; it does not establish a usable menu. Captures are retained locally with the diagnostic probes.

The post-introduction image remains largely black with small corrupted textured regions. Earlier passive probes recorded corruption after the introduction as well; the baseline in this comparison was still displaying movie frames at 110 seconds. Changing or supplying the movie as MP4 would not fix that later graphics issue. Menu navigation, racing, and 60/75 FPS remain unverified. Host presentation rate is not game FPS.

The skip regression and runtime recovery checks passed on Linux and Windows at `ba196e4477c4e1658403e129f0609f117fe981ec` (runs 36931264266 and 36931264042). Windows results are component tests, not native retail boot.

During this rebuild an interrupted compiler left `unity_48_cxx.cxx.o` empty. Recompiling that object completed the link. The POSIX build helper now removes only empty `.o` compiler outputs within its build directory before resuming compilation.

The saved diagnostic executable requires Linux x64, FFmpeg 6.1 shared libraries, and desktop OpenGL/X11. Enable `PS2_DOWNHILL_AUTO_SKIP_INTRO=1` before launch. Game assets are not included. See `docs/AUTO_INTRO_SKIP.md` for the bounded movie gate.
