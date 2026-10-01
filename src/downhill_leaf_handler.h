#pragma once
#include "ps2_runtime.h"

namespace downhill
{
    // Match generated stub wrappers: establish the guest continuation before
    // calling a host handler, including when the EE dispatcher invokes it directly.
    // A handler that transfers/waits may replace this PC; preserve that decision.
    template <PS2Runtime::RecompiledFunction Handler>
    void leafHandler(uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)
    {
        ctx->pc = getRegU32(ctx, 31);
        Handler(rdram, ctx, runtime);
    }
}
