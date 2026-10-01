# Native opening probe

180-second Linux Release/FFmpeg probe with the default guest idle logic, using
verified extracted data and a reconstructed ISO. The three captures are video
opening screens, not menus or rendered race gameplay. `probe.json` records the
stable runner hash and deliberate timeout. `runtime.log` contains an early
return-to-zero diagnostic; execution continued through IOP initialization and
the opening videos. No claim of a diagnostic-free or fully playable game.

- `sony.png`: 30 seconds.
- `copyright.png`: 90 seconds.
- `incog.png`: 175 seconds.

This probe predates the optional idle-wait experiment and timing instrumentation.
