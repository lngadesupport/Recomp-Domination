#include "runtime/gs/ps2_gs_memory.h"
#include <cstdio>
#include <vector>

int main()
{
    GSMem::InitLookupTables();
    std::vector<uint8_t> memory(4 * 1024 * 1024);
    // First 256 writes are unrelated and must not consume the watch budget.
    for (unsigned i = 0; i < 256; ++i)
        GSMem::WriteCT32(memory.data(), 32, 1, 0, 0, i);
    // All three address descriptions land in physical block 6805.
    GSMem::WriteCT32(memory.data(), 6805, 1, 0, 0, 0x800000ff);
    GSMem::WriteCT32(memory.data(), 6804, 1, 8, 0, 0x8000ff00);
    GSMem::WriteCT32(memory.data(), 6805 + 16384, 1, 0, 0, 0x80ff0000);
    if (GSMem::ReadCT32(memory.data(), 6805, 1, 0, 0) != 0x80ff0000) return 1;
    using Access = uint32_t (*)(uint8_t*, uint32_t, uint32_t, uint32_t, uint32_t);
    using Writer = void (*)(uint8_t*, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t);
    struct Format { Writer write; Access read; uint32_t base, mask; };
    const Format formats[] = {
        {GSMem::WriteCT24, GSMem::ReadCT24, 6805, 0xffffff},
        {GSMem::WriteCT16, GSMem::ReadCT16, 6805, 0xffff},
        {GSMem::WriteCT16S, GSMem::ReadCT16S, 6805, 0xffff},
        {GSMem::WriteZ32, GSMem::ReadZ32, 6805 - 24, 0xffffffff},
        {GSMem::WriteZ24, GSMem::ReadZ24, 6805 - 24, 0xffffff},
        {GSMem::WriteZ16, GSMem::ReadZ16, 6805 - 24, 0xffff},
        {GSMem::WriteZ16S, GSMem::ReadZ16S, 6805 - 24, 0xffff},
        {GSMem::WriteP8, GSMem::ReadP8, 6805, 0xff},
        {GSMem::WriteP8H, GSMem::ReadP8H, 6805, 0xff},
        {GSMem::WriteP4, GSMem::ReadP4, 6805, 0xf},
        {GSMem::WriteP4HL, GSMem::ReadP4HL, 6805, 0xf},
        {GSMem::WriteP4HH, GSMem::ReadP4HH, 6805, 0xf},
    };
    for (const auto& format : formats)
    {
        const uint32_t value = 0x1234567 & format.mask;
        format.write(memory.data(), format.base, 1, 0, 0, value);
        if (format.read(memory.data(), format.base, 1, 0, 0) != value) return 3;
    }
    // Last physical block plus one block wraps to block zero.
    GSMem::WriteCT32(memory.data(), 16383, 1, 8, 0, 0x80123456);
    if (GSMem::ReadCT32(memory.data(), 0, 1, 0, 0) != 0x80123456) return 2;
    std::puts("VRAM watch: address aliases and wrap passed");
}
