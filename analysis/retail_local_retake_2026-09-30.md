# Local retake and Windows path regression — 2026-09-30

The two user diagnostic ZIPs describe the same attempt. The ELF identity and extracted-disc configuration passed. CMake failed during tool configuration; the original transcript did not preserve its native output.

A Windows Actions reproduction using the long AppData session layout and portable tools in a directory containing spaces failed while cloning recursive toml11 submodules, reporting `Filename too long`. Moving FetchContent dependencies to a short, per-workspace directory under LocalAppData fixed the reproduced failure. The compiler, synthetic multi-file recompilation, runtime link and GUI startup passed in run 36744417904. Native stdout/stderr and CMake configure logs are now retained. This reproduces and fixes a concrete failure at the user's failing stage; their original ZIP alone does not contain the exact CMake cause.

The real retail Linux runner was executed under a TCP-connected Xvfb display. A bounded diagnostic build sampled guest context at function 0x00246FA0 without changing guest behavior. It confirmed nine physical IRX loads, zero load/open failures and zero HLE fallbacks. The unresolved raw disc read remains LBN 0x10, one sector. No ISO is configured.

The first function entry was PC 0x00246FA0. Subsequent sampled resumes were PC 0x00247058, RA 0x0024708C, within the decrementing retry delay. Generated control flow calls sceSifBindRpc at 0x00247084 for SID 0x80000597, reads the client server field at offset 0x24, and returns to the delay when that field is zero. This narrows the wait to RPC binding; it does not identify a requested asset filename or establish that providing an ISO alone resolves the runtime service.

Nine tick samples reported DMA=0, GIF=0, GS writes=0 and VIF=0, with one active EE thread. DISPFB1=0x1400 and DISPLAY1=0x1BF27F00000000 are seeded in PS2Memory initialization, so they do not establish guest display configuration. Triage now excludes those reset defaults and zero-counter tick labels from graphics progress. The regression fixture and three existing triage cases passed locally.

The watchdog terminated the diagnostic probe after 20.072 seconds. Guest source and the original retail runner were restored after sampling. No first frame, menu, race or retail Windows execution is verified. Re-fetching the previously uploaded multipart archive's first volume again failed with HTTP 502, leaving the full disc unavailable locally.

Proprietary ELF, IRX, generated C++, executable and raw traces remain local. No success stubs or new guest entry points were introduced.
