#include "ps2_runtime.h"
#include "ps2_stubs.h"
#include "runtime/gs/gs_frontend.h"
#include "runtime/gs/gs_types.h"
#include "runtime/ps2_memory.h"
#include <array>
#include <cstdio>
#include <cstring>

int main()
{
    PS2Runtime runtime;
    if (!runtime.memory().initialize()) return 1;
    auto* ram = runtime.memory().getRDRAM();
    struct Image { uint16_t x, y, width, height, base; uint8_t bw, psm; };
    static_assert(sizeof(Image) == 12);
    const std::array<uint32_t, 16> colors{0x800000ff, 0x8000ff00, 0x80ff0000, 0x80123456};
    std::memcpy(ram + 0x5000, colors.data(), sizeof(colors));
    unsigned cases = 0;
    for (const uint16_t base : {uint16_t(1), uint16_t(6753), uint16_t(6805), uint16_t(16383)})
    {
        const Image descriptor{0, 0, 8, 2, base, 1, GS_PSM_CT32};
        std::memcpy(ram + 0x4000, &descriptor, sizeof(descriptor));
        R5900Context ctx{};
        ctx.r[4] = _mm_set_epi64x(0, 0x4000);
        ctx.r[5] = _mm_set_epi64x(0, 0x5000);
        ps2_stubs::sceGsExecLoadImage(ram, &ctx, &runtime);
        if (getRegU32(&ctx, 2) != 0) return 2;
        const uint32_t actual = runtime.gs().ReadVram(GS_PSM_CT32, base, 1, 0, 0);
        if (actual != colors[0])
        {
            std::fprintf(stderr, "SDK upload base=%u actual=%08x expected=%08x\n", base, actual, colors[0]);
            return 3;
        }
        // Readback is independently anchored to a direct GS write at this base.
        runtime.gs().WriteVram(GS_PSM_CT32, base, 1, 0, 0, 0x80765432);
        ctx.r[5] = _mm_set_epi64x(0, 0x6000);
        ps2_stubs::sceGsExecStoreImage(ram, &ctx, &runtime);
        uint32_t stored{};
        std::memcpy(&stored, ram + 0x6000, sizeof(stored));
        if (getRegU32(&ctx, 2) != 0 || stored != 0x80765432) return 4;
        ++cases;
    }
    std::printf("SDK image address: %u nonzero bases passed (upload and independently anchored readback)\n", cases);
}
