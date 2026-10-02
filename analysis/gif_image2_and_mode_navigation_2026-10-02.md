# GIF IMAGE2 support and mode navigation — 2026-10-02

A synthetic production-runtime fixture reproduces a missing GIF IMAGE2 path:
format 2 uploads its pixel payload successfully, while format 3 fails the
same direct GS upload before the patch (exit 2). After the patch, 12 cases
pass across direct GS parsing, native setup+image packets, native DMA upload
chains, wrapped VU1 XGKICK/PATH1, split VIF DIRECT image continuations and
PATH3 image versus DIRECTHL arbitration. No retail code or data is used by
this fixture.

`ps2recomp-gif-image2.patch` accepts FLG 3 as an image transfer consistently
in those five runtime components. The unchanged FLG 2 cases remain covered.
The behavior was checked against PCSX2's primary definitions and GS transfer
implementation:
https://github.com/PCSX2/pcsx2/blob/master/pcsx2/GS/GSRegs.h
https://github.com/PCSX2/pcsx2/blob/master/pcsx2/GS/GSState.cpp

The retail log's `instruction=0xfffffff8` and `instruction=0xfffffffb` messages
are synthetic error identifiers from XGKICK packet processing, rather than
proof that these words were fetched as VU instructions. They respectively
identify the rejected FLG 3 path and oversized packet assembly. Accepting
IMAGE2 fixes the isolated format defect; it does not prove the retail packet
contents are valid or that the mostly empty screen has this cause. Oversized
packets remain unresolved.

The separate 200.027-second dense-capture probe uses the previous immutable
runner (`00cc2f233a5e60f00fc3edba95da0d9e82c5f5c24b714c8134386fa4759ec33b`)
with only seven initial keys. Captures at 110 seconds show a mostly empty
panel, 130 seconds show dim mode-selection text and 190 seconds show bright
mode-selection text. The text becoming visible with no additional input
shows why a single dark transition screenshot cannot establish a stall.
This probe has no nonzero missing target or resource-return anomaly.

42 Python tests pass. Fresh and repeated pinned patch application succeed;
the clean patched runtime diff has SHA-256
`7724c4aeaca48b0144ac27509ab6ee5921a1c8a93a6c0438bd7be4520b477528`.
The IMAGE2 fixture is included in the Linux/Windows production runtime CI.
All four hosted workflows pass for source commit
`b9f21c379f6737810eb13e842e9dd2622b9aa183`: recovery 37076047126,
production GS 37076047124, VIF/SDK/guest/IMAGE2 37076047314 and COP0
37076047150. The IMAGE2 fixture passes on both Linux and Windows.
The new FFmpeg-enabled native Release runner is 44,620,984 bytes with SHA-256
`da2f77f37695e272dd17ec16a04bebf34de18232eea7aacedd065830ea91a2b5`.
The delayed-navigation probe completed 420.038 seconds with unchanged runner
identity. It reaches Event Race (Race/Freeride/Time Trial) at 150 seconds and
Inventory/Bikes at 310 seconds. A capture at 230 seconds remains mostly empty
between these milestones. No nonzero missing target or resource-return
anomaly occurs; the last EE thread remains Ready at 0x238C50. No IMAGE2 reject
marker remains, but 110272 oversized-packet markers are recorded.
Changing the format support does not establish that the remaining packet
contents are valid. The late Start command was not delivered to this probe,
so it is not part of its input evidence. A separate 480-second sequence includes
Start at 360 seconds and is pending.
Incorrect colors, a playable race, game FPS and Windows retail boot remain
unverified.
