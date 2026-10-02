#include "ps2_runtime.h"
#include "ps2_runtime_macros.h"
#include "runtime/ee_scheduler.h"
#include <iostream>
#include <stdexcept>

namespace {
constexpr uint32_t entry = 0x1000u, continuation = 0x2000u;
void leaf(uint8_t *, R5900Context *, PS2Runtime *) {}
void completedWithCheckpoint(uint8_t *, R5900Context *ctx, PS2Runtime *runtime)
{
    runtime->postEeEvent(EeEvent{});
    if (!runtime->eeCheckpointDue()) throw std::runtime_error("fixture checkpoint did not yield");
    ctx->pc = continuation;
}
void loopYield(uint8_t *, R5900Context *ctx, PS2Runtime *runtime)
{
    SET_GPR_U32(ctx, 29, GPR_U32(ctx, 29) - 16u);
    runtime->postEeEvent(EeEvent{});
    if (!runtime->eeCheckpointDue()) throw std::runtime_error("fixture checkpoint did not yield");
    ctx->pc = entry;
}
void dispatchYield(uint8_t *ram, R5900Context *ctx, PS2Runtime *runtime)
{
    SET_GPR_U32(ctx, 29, GPR_U32(ctx, 29) - 16u);
    runtime->postEeEvent(EeEvent{});
    if (runtime->dispatchGuestBranch(ram, ctx, entry, entry + 4u, entry + 8u,
        PS2Runtime::GuestBranchKind::DirectCall, "fixture nested call"))
        throw std::runtime_error("fixture nested dispatch did not yield");
}
bool verify(PS2Runtime::RecompiledFunction function, bool completes)
{
    PS2Runtime runtime;
    if (!runtime.registerFunction(entry, function)) return false;
    R5900Context ctx{};
    SET_GPR_U32(&ctx, 29, 0x4000u);
    const bool result = runtime.dispatchGuestBranch(nullptr, &ctx, entry, 0x800u, continuation,
        PS2Runtime::GuestBranchKind::DirectCall, "fixture call");
    if (result != completes || ctx.pc != (completes ? continuation : entry) ||
        GPR_U32((&ctx), 29) != (completes ? 0x4000u : 0x3ff0u))
    {
        std::cerr << "complete=" << result << " pc=" << std::hex << ctx.pc
                  << " sp=" << GPR_U32((&ctx), 29) << '\n';
        return false;
    }
    return true;
}
}
int main()
{
    if (!verify(leaf, true)) return 1;
    if (!verify(loopYield, false)) return 2;
    if (!verify(dispatchYield, false)) return 3;
    if (!verify(completedWithCheckpoint, true)) return 4;
    std::cout << "Leaf completion and both checkpoint return paths preserve guest PC/SP\n";
}
