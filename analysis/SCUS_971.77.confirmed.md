# SCUS_971.77 - confirmed retail identity

Target: Downhill Domination, final NTSC-U build.

The values below were read directly from the user's legally supplied SCUS_971.77.

## Identity

- Size: 1,691,684 bytes
- SHA-256: ADFDA7B73A8F05FB20A3F0F318772E9D3797FD4D6C0A6C0078AE392DF0F0CF0C
- ELF magic: 7F454C46
- Machine: EM_MIPS (8)
- Entry: 0x0010A008
- PCSX2-style ELF CRC: 0x5AE01D98
- Program headers: 1

## PT_LOAD

- File offset: 0x00001000
- VAddr/PAddr: 0x0010A000
- File size: 0x00193CF0
- Memory size: 0x00796400
- Flags: 0x00000007 (RWX)
- Alignment: 0x00001000
- File-backed guest range: 0x0010A000 .. 0x0029DCF0 exclusive
- Loaded range including zero-fill/BSS: 0x0010A000 .. 0x008A0400 exclusive

Because the single PT_LOAD is RWX, section/function metadata is more trustworthy than blindly treating every file-backed word as code.

## Byte-validated anchors

| Guest PC | Word | Meaning |
|---|---:|---|
| 0x0025C5A0 | 0x0C097110 | JAL to 0x0025C440, sceSifSendCmd candidate |
| 0x0024520C | 0x0C095014 | JAL to 0x00254050, scePadRead candidate |
| 0x001B6740 | 0x0C07EDB0 | JAL to 0x001FB6C0, main candidate |
| 0x00243D34 | 0x30420001 | video/interlace anchor |

The compiler bootstrap re-validates all of these before touching PS2Recomp.
