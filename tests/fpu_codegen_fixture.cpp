// Exercise the production R5900 decoder and emitter, including the retail SQRT word.
#include "ps2recomp/code_generator.h"
#include "ps2recomp/r5900_decoder.h"
#include "ps2recomp/types.h"
#include <fstream>
#include <vector>
using namespace ps2recomp;
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    std::vector<Symbol> symbols; std::vector<Section> sections;
    CodeGenerator generator(symbols, sections); R5900Decoder decoder;
    std::ofstream out(argv[1]);
    const uint32_t ops[]={0x46040104u,
        0x46000004u|(7u<<16)|(3u<<11)|(9u<<6),
        0x46000016u|(7u<<16)|(3u<<11)|(9u<<6),
        0x46000016u|(7u<<16)|(3u<<11)|(3u<<6),
        0x46000016u|(7u<<16)|(3u<<11)|(7u<<6)};
    for(unsigned n=0;n<5;++n) {
        Function fn{}; fn.start=0x3000+n*0x100; fn.end=fn.start+12; fn.isRecompiled=true;
        fn.name="fpu_"+std::to_string(n);
        std::vector<Instruction> inst;
        const uint32_t words[]={ops[n],0x03e00008u,0u};
        for(unsigned i=0;i<3;++i) inst.push_back(decoder.decodeInstruction(fn.start+4*i,words[i]));
        out << generator.generateFunction(fn,inst,false);
    }
    return out ? 0 : 1;
}
