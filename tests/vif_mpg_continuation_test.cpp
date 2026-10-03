#include "runtime/ps2_memory.h"
#include <algorithm>
#include <cstdio>
#include <cstring>
#include <vector>

static void append(std::vector<uint8_t>& packet, uint32_t word) {
    const size_t offset=packet.size();packet.resize(offset+4);
    std::memcpy(packet.data()+offset,&word,4);
}
static void send(PS2Memory& memory,unsigned unit,const uint8_t* data,size_t size) {
    if(unit)memory.processVIF1Data(data,static_cast<uint32_t>(size));
    else memory.processVIF0Data(data,static_cast<uint32_t>(size));
}
int main() {
    unsigned cases=0;
    for(unsigned unit=2;unit-->0;)for(unsigned count:{1u,3u,256u}) {
        PS2Memory memory;if(!memory.initialize())return 1;
        const uint32_t capacity=unit?PS2_VU1_CODE_SIZE:PS2_VU0_CODE_SIZE;
        uint8_t* code=unit?memory.getVU1Code():memory.getVU0Code();
        const unsigned destination=16;
        std::vector<uint8_t> packet;append(packet,0x4a000000u|((count%256u)<<16)|destination);
        // Payload deliberately resembles legal VIF commands. It must never be parsed as commands.
        std::vector<uint8_t> expected(count*8);
        for(unsigned i=0;i<count*2;++i) {
            const uint32_t word=(i%2?0x07002000u:0x4a010010u)+i;
            append(packet,word);std::memcpy(expected.data()+i*4,&word,4);
        }
        append(packet,0x07001234u); // following MARK must execute only after all MPG bytes.
        auto check=[&]() {
            const auto& regs=unit?memory.vif1_regs:memory.vif0_regs;
            return std::memcmp(code+destination*8,expected.data(),expected.size())==0 && regs.mark==0x1234u;
        };
        std::memset(code,0xa5,capacity);send(memory,unit,packet.data(),packet.size());if(!check())return 2;
        const auto wholeGeneration=unit?memory.getVU1CodeGeneration():memory.getVU0CodeGeneration();
        // Every word-aligned DMA boundary, including an MPG-only command fragment.
        for(size_t split=4;split<packet.size();split+=4) {
            std::memset(code,0xa5,capacity);auto& regs=unit?memory.vif1_regs:memory.vif0_regs;regs.mark=0;
            const auto generationBefore=unit?memory.getVU1CodeGeneration():memory.getVU0CodeGeneration();
            send(memory,unit,packet.data(),split);
            const auto generationPartial=unit?memory.getVU1CodeGeneration():memory.getVU0CodeGeneration();
            const size_t firstPayload=std::min(split-4,expected.size());
            if(generationPartial!=generationBefore+(firstPayload?1:0))return 12;
            send(memory,unit,packet.data()+split,packet.size()-split);
            const auto generationAfter=unit?memory.getVU1CodeGeneration():memory.getVU0CodeGeneration();
            if(generationAfter!=generationPartial+(firstPayload<expected.size()?1:0))return 13;
            if(!check()) {std::fprintf(stderr,"MPG split failed: VIF%u count=%u split=%zu\n",unit,count,split);return 3;}
            if(code[destination*8-1]!=0xa5 || code[destination*8+expected.size()]!=0xa5)return 4;
            ++cases;
        }
        // Many 16-byte fragments, as in DMA transfers.
        std::memset(code,0xa5,capacity);
        for(size_t i=0;i<packet.size();i+=16)send(memory,unit,packet.data()+i,std::min<size_t>(16,packet.size()-i));
        if(!check())return 5;
        if((unit?memory.getVU1CodeGeneration():memory.getVU0CodeGeneration())<=wholeGeneration)return 6;
        ++cases;
    }
    for(unsigned unit=0;unit<2;++unit) {
        PS2Memory memory;if(!memory.initialize())return 7;
        const uint32_t mpg=0x4a030010u,mark=0x07005678u;
        send(memory,unit,reinterpret_cast<const uint8_t*>(&mpg),4);
        if(!memory.initialize())return 8;
        send(memory,unit,reinterpret_cast<const uint8_t*>(&mark),4);
        if((unit?memory.vif1_regs.mark:memory.vif0_regs.mark)!=0x5678u)return 9;
        ++cases;
    }
    PS2Memory memory;if(!memory.initialize())return 10;
    const uint32_t mpg=0x4a030010u,mark=0x07009abcu;
    send(memory,1,reinterpret_cast<const uint8_t*>(&mpg),4);
    memory.writeIORegister(0x10003c10u,1u);
    send(memory,1,reinterpret_cast<const uint8_t*>(&mark),4);
    if(memory.vif1_regs.mark!=0x9abcu)return 11;
    ++cases;
    std::printf("VIF MPG: %u fragmented/whole upload cases passed\n",cases);
}
