# VIF colors and SDK clear packet — 2026-10-02

Two further defects have been corrected after the image-address fix. The native rider-selection capture now contains the rider model. Graphics, a complete race and game FPS remain unverified.

## Discriminating observations

Three identity-verified 140-second Linux Release probes used the same owned-display controller: Space, Return, Space with one-second holds and 20-second intervals. These are exploratory captures; wall-clock input does not lock the guest camera or frame timing.

| Stage | Runner SHA-256 | Sampled model pixel writes | Sampled depth rejects | Vertex alpha |
|---|---|---:|---:|---:|
| Triangle diagnostic, before both fixes | `91396dd0ca0e87ce47100e82b2b6a08a26af76e2416c39e56caba4a8257fed97` | 0 | 82 | 1 |
| VIF expansion only | `f5b5dfaba13ef47e90525b25b6503fe70eeb52c7552b8b0c7866af251e96bf75` | 0 | 82 | 128 |
| VIF plus SDK clear packet | `c6a2b213631a0e88fa59cedec022cda8a8d61b445ab403f64ff16fde0e276fa3` | 73 | 9 | 128 |

The bounded texture-8800 sampler captures the first 64 pixel attempts and subsequent powers of two, not every fragment. All before-fix samples fail against stale depth near 16,777,000. After restoring the clear packet, sampled full-screen clears include Z=0 with ALWAYS (TEST=0x30000), followed by restoration of GEQUAL. Model pixel writes now occur; remaining sampled rejects compare against previously rendered model depth. The 70- and 135-second captures show a rider and no stale main-menu text overlay. The screen still has reddish color, dark text, incomplete background and malformed bars.

## Corrections

`UNPACK V4-5` must expand packed five-bit channels into values 0,8,...,248 and the alpha bit into 0 or 128. The pinned VIF1 implementation instead emitted RGB 0..31 and alpha 0..1. The correction shifts RGB by three and alpha by seven. MODE bypass and existing mask/ROW/COL handling are preserved. Independent primary implementation context: [PCSX2 VIF unpacker](https://github.com/PCSX2/pcsx2/blob/master/pcsx2/Vif_Unpack.cpp), `UNPACK_V4_5`.

The pinned `sceGsSetDefClear` handler was a no-op returning zero, but was classified as implemented because it contained no TODO marker. The corrected handler constructs all six A+D pairs: temporary ALWAYS test, sprite primitive, RGBAQ with Q=1, both XYZ vertices with requested Z, restored test, and returns six. Its EE argument layout and packet contents were checked against the actual retail routine at 0x243BE0 by regenerating that guest routine without the stub in scratch. No retail code or assets are included in public evidence.

Optional diagnostics `PS2_TRACE_GS_TRIANGLE_TBP=8800` and `PS2_TRACE_GS_CLEAR_DEPTH=1` do not alter rendering. The triangle selector rejects malformed, negative and out-of-range input. Samples are bounded to initial records plus powers of two. Native input runs use a controller in the same execution namespace as their own Xvfb.

## Validation

- Real production VIF1 processing passes 131,136 cases: every 16-bit color with both USN settings, NUM=0, MODE bypass, masked ROW/COL/protect and memory wrap. The original implementation fails at color 0x0001 with channel value 1 instead of 8.
- Real SDK clear processing passes 16 independently anchored packet cases and resets a stale maximum depth before restoring GEQUAL. The original handler fails with a zero return and unchanged packet.
- All 28 production renderer CTest entries pass with ASan/UBSan; all 34 Python tests pass.
- The full patch chain applies to a fresh pinned checkout and reapplies with identical tracked changes.
- Source commit `05f5a0c649117e974d1ffad0c21f478a84fc4420` passes hosted production renderer [37007970509](https://github.com/lngadesupport/Recomp-Domination/actions/runs/37007970509), runtime recovery [37007970438](https://github.com/lngadesupport/Recomp-Domination/actions/runs/37007970438), COP0 [37007970558](https://github.com/lngadesupport/Recomp-Domination/actions/runs/37007970558), and real VIF/SDK fixture [37007970494](https://github.com/lngadesupport/Recomp-Domination/actions/runs/37007970494) workflows on Linux and Windows. This validates components, not a Windows retail-game executable.

## Next investigation

Follow the remaining color/composition defects with a fixed scene. The reddish rider still implicates texture/fog/lighting or blending state; the current evidence does not identify one cause. An identity-verified 240-second Space/Return navigation probe ended on a black capture. It does not establish a race or a stall. Inspection found SDK `applyKeyboardState` maps Cross to X, whereas the separate low-level pad path accepts Space. The controller default now uses X; explicit recorded Space inputs remain preserved in the comparative evidence. A separate X/Return probe uses the SDK mapping; its 120-second capture still labels Select Rider and no longer contains the rider. Recent sampled thread snapshots report running=0 and thread 1 status=5 at PC 0x1031210. The probe completed its 240-second limit with the same verified runner; the 235-second capture again contains the rider on Select Rider. These observations do not identify the cause, confirm responsiveness or certify a race. No game FPS is inferred from host presentation ticks.
