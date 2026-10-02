#include "runtime/gs/gs_frontend.h"
#include "runtime/gs/ps2_gif_arbiter.h"
#include "runtime/ps2_memory.h"
#include "runtime/ps2_vu1.h"
#include <array>
#include <cstdio>
#include <cstring>
#include <vector>

static uint64_t tag(unsigned format, unsigned loops=1) {
    return loops | (1ull<<15) | (uint64_t(format)<<58);
}
int main() {
    unsigned cases=0;
    for(unsigned format : {2u,3u}) {
        PS2Memory mem;
        if(!mem.initialize()) return 1;
        GS gs; gs.init(mem.getGSVRAM(),PS2_GS_VRAM_SIZE,&mem.gs());
        const uint64_t bitblt=1ull<<48;
        auto setup=[&] {gs.writeRegister(GS_REG_BITBLTBUF,bitblt);gs.writeRegister(GS_REG_TRXPOS,0);gs.writeRegister(GS_REG_TRXREG,4ull|(1ull<<32));gs.writeRegister(GS_REG_TRXDIR,0);};
        const std::array<uint32_t,4> pixels{0x80112233u,0xff445566u,0x40778899u,0x00aabbccu};
        auto check=[&] {for(unsigned x=0;x<4;++x) if(gs.ReadVram(GS_PSM_CT32,0,1,x,0)!=pixels[x]) return false;return true;};
        std::array<uint64_t,4> packet{tag(format),0,0,0};std::memcpy(packet.data()+2,pixels.data(),16);
        setup(); gs.processGIFPacket(reinterpret_cast<const uint8_t*>(packet.data()),32);
        if(!check()) {std::fprintf(stderr,"GIF format %u: direct GS upload failed\n",format);return 2;} ++cases;
        std::memset(mem.getGSVRAM(),0,PS2_GS_VRAM_SIZE); setup();
        // A canonical setup+image packet must use the GS native upload path.
        std::memset(mem.getGSVRAM(),0,PS2_GS_VRAM_SIZE);
        std::array<uint64_t,14> native{4ull|(1ull<<60),0xe,bitblt,GS_REG_BITBLTBUF,0,GS_REG_TRXPOS,4ull|(1ull<<32),GS_REG_TRXREG,0,GS_REG_TRXDIR,tag(format),0,0,0};
        std::memcpy(native.data()+12,pixels.data(),16);
        const auto uploadCount=gs.nativeImageUploadCount();
        gs.processGIFPacket(reinterpret_cast<const uint8_t*>(native.data()),sizeof(native));
        if(!check() || gs.nativeImageUploadCount()!=uploadCount+1) {std::fprintf(stderr,"GIF format %u: native GS packet failed\n",format);return 6;} ++cases;
        // The DMA fast path recognizes the same setup and a REF image payload.
        std::memset(mem.getGSVRAM(),0,PS2_GS_VRAM_SIZE);
        constexpr unsigned chain=0x28000, payload=0x29000;
        auto* ram=mem.getRDRAM();std::memset(ram+chain,0,160);
        auto put=[&](unsigned offset,uint64_t value){std::memcpy(ram+chain+offset,&value,8);};
        put(0,5ull|(1ull<<28));std::memcpy(ram+chain+16,native.data(),80);
        put(96,1ull|(1ull<<28));std::memcpy(ram+chain+112,packet.data(),16);
        put(128,1ull|(3ull<<28)|(uint64_t(payload)<<32));put(144,7ull<<28);
        std::memcpy(ram+payload,pixels.data(),16);
        if(!mem.tryProcessNativeGifImageUploadChain(gs,chain,0x105u) || !check() || gs.nativeImageUploadCount()!=uploadCount+2) {std::fprintf(stderr,"GIF format %u: native DMA chain failed\n",format);return 7;} ++cases;
        // PATH1 crosses the end of VU memory; the image payload starts at zero.
        const unsigned last=PS2_VU1_DATA_SIZE/16-1;
        std::memcpy(mem.getVU1Data()+last*16,packet.data(),16);
        std::memcpy(mem.getVU1Data(),pixels.data(),16);
        const uint32_t kick=(0x40u<<25)|(1u<<11)|(0x6cu<<4)|0x3cu;
        const uint32_t nop=0x2ffu;
        std::memcpy(mem.getVU1Code(),&kick,4); std::memcpy(mem.getVU1Code()+4,&nop,4);
        std::vector<std::vector<uint8_t>> captured;
        mem.setGifPacketCallback([&](const uint8_t* p,uint32_t n){captured.emplace_back(p,p+n);gs.processGIFPacket(p,n);});
        VU1Interpreter vu; vu.state().vi[1]=last;
        vu.execute(mem.getVU1Code(),PS2_VU1_CODE_SIZE,mem.getVU1Data(),PS2_VU1_DATA_SIZE,gs,&mem,0,0,0,3);
        if(captured.size()!=1 || captured[0].size()!=32 || std::memcmp(captured[0].data(),packet.data(),32) || !check()) {std::fprintf(stderr,"GIF format %u: wrapped XGKICK failed\n",format);return 3;} ++cases;
        // DIRECT carries only the GIFtag; the next raw VIF input is image data.
        std::memset(mem.getGSVRAM(),0,PS2_GS_VRAM_SIZE);setup();captured.clear();
        std::array<uint32_t,5> direct{0x50000001u,0,0,0,0};std::memcpy(direct.data()+1,packet.data(),16);
        mem.processVIF1Data(reinterpret_cast<const uint8_t*>(direct.data()),20);
        mem.processVIF1Data(reinterpret_cast<const uint8_t*>(pixels.data()),16);
        if(!check()) {std::fprintf(stderr,"GIF format %u: split DIRECT continuation failed\n",format);return 4;} ++cases;
        // DIRECTHL must wait behind PATH3 image uploads, including IMAGE2.
        std::vector<unsigned> order;
        GifArbiter arb([&](const uint8_t* p,uint32_t){order.push_back(p[8]);});
        auto image=packet;auto packed=packet;image[1]=3;packed[0]=tag(0,0);packed[1]=2;
        arb.submit(GifPathId::Path2,reinterpret_cast<const uint8_t*>(packed.data()),16,true);
        arb.submit(GifPathId::Path3,reinterpret_cast<const uint8_t*>(image.data()),32);
        arb.drain();
        if(order!=std::vector<unsigned>{3,2}) {std::fprintf(stderr,"GIF format %u: DIRECTHL arbitration failed\n",format);return 5;} ++cases;
    }
    std::printf("GIF IMAGE/IMAGE2: %u direct/native uploads, wrapped PATH1, split DIRECT and arbitration cases passed\n",cases);
}
