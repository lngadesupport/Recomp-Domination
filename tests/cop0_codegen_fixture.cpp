// Generates executable regression fixtures through the production decoder/emitter.
#include "ps2recomp/code_generator.h"
#include "ps2recomp/r5900_decoder.h"
#include "ps2recomp/types.h"
#include <fstream>
#include <vector>
using namespace ps2recomp;
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    std::vector<Symbol> symbols;
    std::vector<Section> sections;
    CodeGenerator generator(symbols, sections);
    R5900Decoder decoder;
    std::ofstream out(argv[1]);
    for (unsigned rt=0; rt<4; ++rt) {
        // Branch outcome in v0; delay-slot execution count in v1.
        const uint32_t base=0x1000+rt*0x100;
        const uint32_t words[]={0x24020001u, 0x41000003u|(rt<<16),
            0x24630001u, 0, 0x24020000u, 0x03e00008u, 0x2c420001u};
        Function fn{}; fn.name="cop0_"+std::to_string(rt); fn.start=base;
        fn.end=base+sizeof(words); fn.isRecompiled=true;
        std::vector<Instruction> inst;
        for (unsigned i=0;i<7;++i) inst.push_back(decoder.decodeInstruction(base+4*i,words[i]));
        out << generator.generateFunction(fn,inst,false);
    }
    // Exact instruction words from retail function 0x217D88, with its NOP delay slot.
    const uint32_t words[]={0x24020001,0x41010003,0,0,0x24020000,0x03e00008,0x2c420001};
    Function fn{}; fn.name="retail_dma_busy"; fn.start=0x217d88;
    fn.end=fn.start+sizeof(words);fn.isRecompiled=true;
    std::vector<Instruction> inst;
    for(unsigned i=0;i<7;++i)inst.push_back(decoder.decodeInstruction(fn.start+4*i,words[i]));
    out << generator.generateFunction(fn,inst,false);
    return out ? 0 : 1;
}
