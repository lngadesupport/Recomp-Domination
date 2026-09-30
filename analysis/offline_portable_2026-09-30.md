# Portable offline validation — 2026-09-30

The Windows portable package now includes LLVM-MinGW, CMake, Ninja, MinGit, the pinned PS2Recomp checkout, and source snapshots for ELFIO, toml11, fmt, libdwarf, Rabbitizer, nlohmann/json and raylib. Original license files are retained.

The launcher copies the public upstream checkout into its writable session. CMake receives explicit FETCHCONTENT_SOURCE_DIR overrides and FULLY_DISCONNECTED/UPDATES_DISCONNECTED. Missing sources or a missing pinned commit stop the offline build instead of cloning or fetching. FFmpeg remains disabled.

Validation:
- Windows run https://github.com/lngadesupport/Recomp-Domination/actions/runs/36748627827 succeeded at commit d0445ee62b15cb358b86662ed45cd3cabd8bd7ed.
- A clean Windows compiler, analyzer and synthetic runtime build succeeded with HTTP/HTTPS/ALL_PROXY pointing at a closed localhost port and Git network protocols disabled. Paths include spaces in the tool directory and the long launcher session hierarchy.
- A clean local Linux build of the compiler/analyzer succeeded with network access disabled for those operations; runtime configuration also succeeded using existing local desktop dependencies.
- The newly built local recompiler processed the real SCUS_971.77 ELF successfully and generated 5,528 C++ files offline. Retail game files and generated retail code were kept local.

This validates the offline compilation path. It does not establish working menus, rendering or a playable race. The previously recorded SIF RPC binding blocker still requires further runtime work and full disc data.
