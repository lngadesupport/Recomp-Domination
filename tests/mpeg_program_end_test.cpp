#include "ps2_runtime.h"
#include "ps2_stubs.h"
#include "ps2_runtime_macros.h"
#include "Kernel/Stubs/MPEG.h"
#include <cstring>
#include <iostream>

int main()
{
    PS2Runtime runtime;
    if (!runtime.memory().initialize()) return 2;
    auto *rdram = runtime.memory().getRDRAM();
    constexpr uint32_t handle = 0x4000u, data = 0x5000u;
    R5900Context ctx{};
    SET_GPR_U32((&ctx), 4, handle);
    ps2_stubs::resetMpegStubState();
    ps2_stubs::notifyMpegCdStreamStart(&runtime);
    const uint8_t end[] = {0, 0, 1, 0xB9};
    std::memcpy(rdram + data, end, sizeof(end));
    SET_GPR_U32((&ctx), 5, data); SET_GPR_U32((&ctx), 6, sizeof(end));
    ps2_stubs::sceMpegDemuxPss(rdram, &ctx, &runtime);
    ps2_stubs::sceMpegIsEnd(rdram, &ctx, &runtime);
    if (GPR_U32((&ctx), 2) != 1u) { std::cerr << "program end not recognized before CD EOF\n"; return 1; }
    ps2_stubs::enqueueMpegDecodedFrameForTesting(handle);
    ps2_stubs::sceMpegIsEnd(rdram, &ctx, &runtime);
    if (GPR_U32((&ctx), 2) != 0u) { std::cerr << "queued picture discarded by early end\n"; return 1; }
    ps2_stubs::notifyMpegCdStreamStart(&runtime);
    ps2_stubs::sceMpegIsEnd(rdram, &ctx, &runtime);
    if (GPR_U32((&ctx), 2) != 0u) return 1;
    const uint8_t sequence[] = {0, 0, 1, 0xB7};
    std::memcpy(rdram + data, sequence, sizeof(sequence));
    ps2_stubs::sceMpegAddBs(rdram, &ctx, &runtime);
    ps2_stubs::sceMpegIsEnd(rdram, &ctx, &runtime);
    if (GPR_U32((&ctx), 2) != 0u) return 1;
    std::cout << "program end accepted; queued picture, fresh generation, sequence-only end preserved\n";
}
