// Positive finite operands isolate register selection and numerator semantics.
// This fixture does not certify PS2 FPU exception, denormal, or saturation behavior.
#include <cmath>
#include <cstdint>
#include <iostream>
struct R5900Context { uint64_t regs[32]{}; float f[32]{}; uint32_t pc{},branch_pc{}; bool in_delay_slot{}; };
struct PS2Runtime {};
#define GPR_U32(c,n) uint32_t((c)->regs[n])
#define FPU_SQRT_S(v) sqrtf(v)
#include "fpu-generated.inc"
int main() {
    using Fn=void(*)(uint8_t*,R5900Context*,PS2Runtime*);
    const Fn cases[]={Errorfunc_3000,Errorfunc_3100,Errorfunc_3200,Errorfunc_3300,Errorfunc_3400};
    const unsigned dest[]={4,9,9,3,7};
    PS2Runtime runtime; unsigned count=0;
    for(float square : {4.0f,9.0f,16.0f,64.0f}) {
        for(float numerator : {2.0f,6.0f,12.0f}) {
            for(unsigned n=0;n<5;++n) {
                R5900Context c{}; c.regs[31]=0x76543210;
                c.f[0]=121.0f; c.f[4]=square; c.f[3]=numerator; c.f[7]=square;
                const float expected=n<2 ? std::sqrt(square) : numerator/std::sqrt(square);
                cases[n](nullptr,&c,&runtime);
                if(c.f[dest[n]]!=expected || c.pc!=c.regs[31] || c.in_delay_slot) {
                    std::cerr << "FAIL variant="<<n<<" square="<<square<<" numerator="<<numerator
                              <<" actual="<<c.f[dest[n]]<<" expected="<<expected<<'\n'; return 1;
                }
                ++count;
            }
        }
    }
    std::cout << "PASS generated_fpu_executions="<<count<<" retail_sqrt=12 alias_variants=2\n";
}
