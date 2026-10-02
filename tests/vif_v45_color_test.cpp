#include "runtime/ps2_memory.h"
#include <array>
#include <cstdio>
#include <cstring>
#include <vector>

static void append(std::vector<uint8_t>& packet, uint32_t word)
{
    const size_t offset = packet.size();
    packet.resize(offset + 4);
    std::memcpy(packet.data() + offset, &word, 4);
}

int main()
{
    PS2Memory memory;
    if (!memory.initialize()) return 1;
    // Channel ramp and binary alpha expectations are independent of unpack code.
    constexpr std::array<uint32_t,32> ramp{0,8,16,24,32,40,48,56,64,72,80,88,96,104,112,120,
        128,136,144,152,160,168,176,184,192,200,208,216,224,232,240,248};
    unsigned cases = 0;
    for (unsigned usn = 0; usn < 2; ++usn)
    for (unsigned base = 0; base < 65536u; base += 256u)
    {
        std::vector<uint8_t> packet;
        append(packet, 0x01000101u); // STCYCL 1:1
        append(packet, 0x6f000000u | (usn ? 0x4000u : 0u)); // NUM=0 means 256
        for (unsigned pair = 0; pair < 256; pair += 2)
            append(packet, (base + pair) | ((base + pair + 1u) << 16));
        memory.processVIF1Data(packet.data(), static_cast<uint32_t>(packet.size()));
        for (unsigned n = 0; n < 256; ++n)
        {
            const unsigned color = base + n;
            const std::array<uint32_t,4> expected{ramp[color % 32u],ramp[(color / 32u) % 32u],
                ramp[(color / 1024u) % 32u],color >= 32768u ? 128u : 0u};
            std::array<uint32_t,4> actual{};
            std::memcpy(actual.data(), memory.getVU1Data() + n * 16u, 16);
            if (actual != expected)
            {
                std::fprintf(stderr,"V4-5 color=%04x usn=%u actual=%u,%u,%u,%u expected=%u,%u,%u,%u\n",
                    color,usn,actual[0],actual[1],actual[2],actual[3],expected[0],expected[1],expected[2],expected[3]);
                return 2;
            }
            ++cases;
        }
    }
    // MODE must not add ROW to compressed colors. Mask selects data/ROW/COL/protect.
    for (unsigned mode = 0; mode < 4; ++mode)
    for (unsigned usn = 0; usn < 2; ++usn)
    {
        for (unsigned field=0;field<4;++field) {
            memory.vif1_regs.row[field]=1000u+field;
            memory.vif1_regs.col[field]=2000u+field;
        }
        std::memset(memory.getVU1Data(),0x55,PS2_VU1_DATA_SIZE);
        std::vector<uint8_t> packet;
        append(packet,0x01000101u); append(packet,0x05000000u | mode);
        append(packet,0x20000000u); append(packet,0xe4e4e4e4u); // mask: data,ROW,COL,protect
        append(packet,0x7f0803fcu | (usn ? 0x4000u : 0u)); // 8 vectors, wrapping end of VU RAM
        for (unsigned n=0;n<4;++n) append(packet,0xffffffffu);
        memory.processVIF1Data(packet.data(),static_cast<uint32_t>(packet.size()));
        for (unsigned n=0;n<8;++n) {
            std::array<uint32_t,4> actual{};
            std::memcpy(actual.data(),memory.getVU1Data()+((1020u+n)%1024u)*16u,16);
            const std::array<uint32_t,4> expected{248u,1001u,2000u,0x55555555u};
            if(actual!=expected) return 3;
            ++cases;
        }
        if(memory.vif1_regs.row[0]!=1000u || memory.vif1_regs.row[1]!=1001u) return 4;
    }
    std::printf("VIF V4-5: %u cases passed (all colors, USN, MODE, masks, wrap, NUM=0)\n",cases);
}
