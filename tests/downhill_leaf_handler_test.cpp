#include "downhill_leaf_handler.h"
#include <cassert>
#include <cstdint>

namespace {
unsigned calls;
void copyHandler(uint8_t *memory, R5900Context *ctx, PS2Runtime *) {
    ++calls;
    // The generated wrapper presents the return PC to the handler already.
    assert(ctx->pc == getRegU32(ctx, 31));
    memory[getRegU32(ctx, 4)] = memory[getRegU32(ctx, 5)];
    ctx->r[2] = ctx->r[4];
}
void transferHandler(uint8_t *, R5900Context *ctx, PS2Runtime *) {
    ctx->pc = 0x123456;
}
}
int main() {
    uint8_t memory[8] = {0, 0x42};
    R5900Context ctx{};
    ctx.pc = 0x254050;
    ctx.r[31] = _mm_set_epi64x(0, 0x240bb4);
    ctx.r[4] = _mm_set_epi64x(0, 2);
    ctx.r[5] = _mm_set_epi64x(0, 1);
    downhill::leafHandler<copyHandler>(memory, &ctx, nullptr);
    assert(calls == 1 && ctx.pc == 0x240bb4 && memory[2] == 0x42);
    assert(getRegU32(&ctx, 2) == 2 && getRegU32(&ctx, 4) == 2 && getRegU32(&ctx, 5) == 1);
    // Also valid on an ordinary nested call, where dispatch expects fallthrough.
    ctx.pc = 0x254050;
    downhill::leafHandler<copyHandler>(memory, &ctx, nullptr);
    assert(calls == 2 && ctx.pc == 0x240bb4);
    downhill::leafHandler<transferHandler>(memory, &ctx, nullptr);
    assert(ctx.pc == 0x123456);
}
