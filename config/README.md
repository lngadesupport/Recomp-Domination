# Generated configuration

BUILD_DOWNHILL.cmd writes config/downhill.auto.toml locally after running ps2_analyzer.

The generated file is intentionally ignored by Git because it contains machine-local absolute paths. The bootstrap then preserves analyzer findings and injects only build-specific values that have been validated against SCUS_971.77:

- entry 0x0010A008
- main candidate 0x001FB6C0
- scePadRead 0x00254050
- sceSifSendCmd 0x0025C440

If analysis/SCUS_971.77.functions.csv exists, the bootstrap also enables that Ghidra function map automatically.
