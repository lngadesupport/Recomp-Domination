#include "ps2_runtime.h"
#include <cstring>
#include <iostream>
#include <sstream>

int main(int argc, char **argv)
{
    const bool enabled = argc > 1 && std::strcmp(argv[1], "enabled") == 0;
    PS2Runtime runtime;
    runtime.setMissingFunctionPolicy(PS2Runtime::MissingFunctionPolicy::ContinueToTarget);
    uint8_t ram[64]{};
    const uint32_t words[4]{0x27bdfff0, 0xafbf0000, 0x03e00008, 0x00000000};
    std::memcpy(ram + 16, words, sizeof(words));
    R5900Context context{};
    std::ostringstream captured;
    auto *old = std::cerr.rdbuf(captured.rdbuf());
    // Zero is the normal invocation-return sentinel. It must not consume
    // the budget needed for a later real missing target.
    for (unsigned i = 0; i < 65; ++i)
        runtime.reportMissingFunction(ram, &context, 0, 4,
            PS2Runtime::GuestBranchKind::Return, "zero-return");
    runtime.resetMissingFunctionReportOnce();
    for (unsigned i = 0; i < 66; ++i)
    {
        runtime.reportMissingFunction(i == 1 ? nullptr : ram, &context, 16, 4,
            PS2Runtime::GuestBranchKind::Return, "fixture");
        if (context.pc != 16) { std::cerr.rdbuf(old); return 1; }
    }
    // Null memory and an address at the RAM boundary must remain safe.
    runtime.resetMissingFunctionReportOnce();
    runtime.reportMissingFunction(nullptr, &context, 0xffffffff, 4,
        PS2Runtime::GuestBranchKind::Return, "boundary");
    std::cerr.rdbuf(old);
    const auto log = captured.str();
    unsigned records = 0;
    for (size_t pos = 0; (pos = log.find("[guest-branch:missing-target]", pos)) != std::string::npos; ++pos) ++records;
    if (records != (enabled ? 35u : 3u)) return 2;
    if (enabled && (log.find("sample=64") == std::string::npos ||
        log.find("target[0]=0x27bdfff0") == std::string::npos ||
        log.find("targetReadable=no") == std::string::npos ||
        log.find("sample=33") != std::string::npos)) return 3;
    if (!enabled && log.find("sample=") != std::string::npos) return 4;
    std::cout << "Missing-target trace: sampling, target words, boundary and PC preservation passed\n";
}
