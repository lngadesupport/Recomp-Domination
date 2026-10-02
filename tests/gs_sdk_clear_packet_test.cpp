#include "ps2_runtime.h"
#include "ps2_stubs.h"
#include "runtime/gs/gs_frontend.h"
#include <array>
#include <cstdio>
#include <cstring>

int main()
{
    PS2Runtime runtime;
    if (!runtime.memory().initialize() || !runtime.syncCoreSubsystems()) return 1;
    auto* ram=runtime.memory().getRDRAM();
    unsigned cases=0;
    for(uint32_t ztest=0;ztest<4;++ztest)
    for(uint32_t depth : {0u,0x123456u,0xffffffu,0xffffffffu})
    {
        std::memset(ram+0x3ff0,0x55,128);
        R5900Context ctx{};
        auto reg=[&](int r,uint32_t v){ctx.r[r]=_mm_set_epi64x(0,v);};
        reg(4,0x4000);reg(5,ztest);reg(6,1728);reg(7,1936);reg(8,640);reg(9,224);
        reg(10,12);reg(11,34);reg(29,0x6000);
        ram[0x6000]=56;ram[0x6008]=78;std::memcpy(ram+0x6010,&depth,4);
        ps2_stubs::sceGsSetDefClear(ram,&ctx,&runtime);
        const std::array<uint64_t,12> expected{0x30000u,0x47u,6u,0u,0x3f8000004e38220cull,1u,
            (uint64_t(depth)<<32)|(uint64_t(1936u*16u)<<16)|(1728u*16u),5u,
            (uint64_t(depth)<<32)|(uint64_t(2160u*16u)<<16)|(2368u*16u),5u,
            ztest ? (uint64_t(ztest)<<17)|0x10000u : 0x30000u,0x47u};
        std::array<uint64_t,12> actual{};std::memcpy(actual.data(),ram+0x4000,96);
        if(getRegU32(&ctx,2)!=6 || actual!=expected) {std::fprintf(stderr,"SDK clear packet mismatch ztest=%u depth=%u return=%u\n",ztest,depth,getRegU32(&ctx,2));return 2;}
        for(unsigned n=0;n<16;++n) if(ram[0x3ff0+n]!=0x55 || ram[0x4060+n]!=0x55) return 3;
        ++cases;
    }
    // The real packet must clear a stale maximum Z before restoring GEQUAL.
    R5900Context ctx{};
    auto reg=[&](int r,uint32_t v){ctx.r[r]=_mm_set_epi64x(0,v);};
    reg(4,0x4000);reg(5,2);reg(8,4);reg(9,4);reg(29,0x6000);
    std::memset(ram+0x6000,0,24);
    ps2_stubs::sceGsSetDefClear(ram,&ctx,&runtime);
    auto &gs=runtime.gs();
    gs.writeRegister(GS_REG_FRAME_1,4u|(1ull<<16));
    gs.writeRegister(GS_REG_ZBUF_1,1ull<<24); // Z24 at page 0, writable
    gs.writeRegister(GS_REG_SCISSOR_1,(3ull<<16)|(3ull<<48));
    gs.WriteVram(GS_PSM_Z24,0,1,1,1,0xffffff);
    std::array<uint64_t,12> pairs{};std::memcpy(pairs.data(),ram+0x4000,96);
    for(unsigned n=0;n<12;n+=2) gs.writeRegister(uint8_t(pairs[n+1]),pairs[n]);
    if(gs.ReadVram(GS_PSM_Z24,0,1,1,1)!=0) return 4;
    if(gs.getDebugSnapshot().ctx[0].test!=0x50000u) return 5;
    std::printf("SDK clear: %u packet cases and stale-depth reset passed\n",cases);
}
