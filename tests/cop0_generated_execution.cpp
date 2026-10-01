// Executes production-generated functions with a small MMIO/runtime test double.
// This does not emulate DMA transfers or assert that the full game boots.
#include "runtime/ps2_cop0_condition.h"
#include <cstdint>
#include <iostream>
#include <stdexcept>
struct R5900Context {
    uint64_t regs[32]{};
    uint32_t pc{}, branch_pc{};
    bool in_delay_slot{};
};
struct TestMemory {
    uint32_t status{}, selected{}, reads{};
    uint32_t read32(uint32_t address) {
        ++reads;
        if (address == 0x1000E010u) return status;
        if (address == 0x1000E020u) return selected;
        throw std::runtime_error("unexpected MMIO address");
    }
};
struct PS2Runtime {
    TestMemory mmio;
    TestMemory &memory() { return mmio; }
};
#define GPR_U32(c,n) uint32_t((c)->regs[n])
#define GPR_U64(c,n) ((c)->regs[n])
#define SET_GPR_S32(c,n,v) ((c)->regs[n] = uint64_t(int64_t(int32_t(v))))
#define SET_GPR_U64(c,n,v) ((c)->regs[n] = uint64_t(v))
#define ADD32(a,b) (uint32_t(a)+uint32_t(b))
#include "cop0-generated.inc"
int main() {
    using Fn=void(*)(uint8_t*,R5900Context*,PS2Runtime*);
    const Fn variants[]={Errorfunc_1000,Errorfunc_1100,Errorfunc_1200,Errorfunc_1300};
    uint64_t executions=0;
    PS2Runtime runtime;
    // Exhaustive selected/completed channel combinations; high bits must be ignored.
    for (uint32_t selected=0;selected<1024;++selected) {
        for (uint32_t status=0;status<1024;++status) {
            bool ready=true;
            for (unsigned channel=0;channel<10;++channel)
                if ((selected&(1u<<channel)) && !(status&(1u<<channel))) ready=false;
            runtime.mmio.status=status|0xfffffc00u;
            runtime.mmio.selected=selected|0xfffffc00u;
            for(unsigned rt=0;rt<4;++rt) {
                R5900Context ctx{};ctx.regs[31]=0x76543210;
                runtime.mmio.reads=0;
                variants[rt](nullptr,&ctx,&runtime);
                const bool taken=(rt&1) ? ready : !ready;
                const uint64_t expectedDelay=(rt&2) ? taken : 1;
                if(ctx.regs[2]!=uint64_t(!taken) || ctx.regs[3]!=expectedDelay ||
                    ctx.pc!=ctx.regs[31] || ctx.in_delay_slot || runtime.mmio.reads!=2) {
                    std::cerr << "FAIL selected="<<selected<<" status="<<status<<" rt="<<rt<<'\n';
                    return 1;
                }
                ++executions;
            }
            R5900Context ctx{};ctx.regs[31]=0x76543210;
            runtime.mmio.reads=0;
            Errorfunc_217d88(nullptr,&ctx,&runtime);
            if(ctx.regs[2]!=uint64_t(!ready) || ctx.pc!=ctx.regs[31] || runtime.mmio.reads!=2) {
                std::cerr << "FAIL retail DMA busy predicate\n";return 1;
            }
            ++executions;
        }
    }
    std::cout << "PASS generated_executions="<<executions
        <<" channel_states=1048576 branch_variants=4 retail_predicates=1048576\n";
}
