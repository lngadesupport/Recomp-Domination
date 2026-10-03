// Compile the production opt-in observers in this TU to verify passthrough.
#include "../src/downhill_domination_overrides.cpp"
#include <vector>
#include <array>
#include <stdexcept>
namespace {
void observedWait(uint8_t *ram, R5900Context *ctx, PS2Runtime *) {
    SET_GPR_U32(ctx, 2, GPR_U32(ctx, 2) + 7u);
    ctx->f[12] = 3.25f;
    ctx->pc = 0x238c70u;
    Ps2FastWrite32(ram, 0x4000u, 0xabcdef01u);
}
void observedNumeric(uint8_t *ram, R5900Context *ctx, PS2Runtime *) {
    SET_GPR_U32(ctx, 29, 0x8020u);
    SET_GPR_U32(ctx, 31, 0x1000u);
    ctx->pc = 0x1000u;
    Ps2FastWrite32(ram, 0x8010u, 0x1000u);
}
}
int main() {
    PS2Runtime runtime;
    runtime.registerFunction(0x1000u, observedWait);
    std::vector<uint8_t> initial(PS2_RAM_SIZE);
    Ps2FastWrite32(initial.data(), 0x8018u, 0x1000u);
    const uint64_t counts[]={0u,3u,119u,120u,61439u,61440u};
    originalFrameWait = observedWait;
    originalNumericDisplay = observedNumeric;
    unsigned tested = 0;
    for (uint32_t pc : {0x238c00u,0x238c50u,0x238c64u,0x238c70u}) {
        for (uint64_t count : counts) {
            auto directRam = initial, tracedRam = initial;
            R5900Context direct{};
            direct.pc=pc; SET_GPR_U32(&direct,29,pc==0x238c00u?0x8020u:0x8000u);
            SET_GPR_U32(&direct,31,0x1000u);
            auto traced = direct;
            frameStateCalls=count;
            observedWait(directRam.data(),&direct,&runtime);
            downhillTraceFrameState(tracedRam.data(),&traced,&runtime);
            if(std::memcmp(&direct,&traced,sizeof(direct)) || directRam!=tracedRam || frameStateCalls!=count+1u) return 1;
            ++tested;
        }
    }
    for(uint32_t pc : {0x177da0u,0x177e68u,0x177e78u}) {
        auto directRam=initial,tracedRam=initial;R5900Context direct{};
        direct.pc=pc; SET_GPR_U32(&direct,29,pc==0x177da0u?0x8030u:0x8000u);
        SET_GPR_U32(&direct,31,0x1000u);auto traced=direct;
        numericDisplayCalls=numericDisplayAnomalies=0;
        observedNumeric(directRam.data(),&direct,&runtime);
        downhillTraceNumericDisplay(tracedRam.data(),&traced,&runtime);
        if(std::memcmp(&direct,&traced,sizeof(direct)) || directRam!=tracedRam || numericDisplayCalls!=1u) return 2;
        ++tested;
    }
    std::cout << "PASS frame_state_passthrough_cases=" << tested << '\n';
}
