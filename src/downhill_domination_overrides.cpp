#include "game_overrides.h"
#include "ps2_runtime.h"

#include <cstdint>
#include <iostream>

namespace
{
    constexpr uint32_t kEntryPoint = 0x0010A008u;
    constexpr uint32_t kScePadRead = 0x00254050u;
    constexpr uint32_t kSceSifSendCmd = 0x0025C440u;

    void applyDownhillDominationOverrides(PS2Runtime &runtime)
    {
        const bool padBound =
            ps2_game_overrides::bindAddressHandler(runtime, kScePadRead, "scePadRead");

        const bool sifBound =
            ps2_game_overrides::bindAddressHandler(runtime, kSceSifSendCmd, "sceSifSendCmd");

        if (!padBound)
        {
            std::cerr << "[downhill] failed to bind scePadRead at 0x00254050\n";
        }

        if (!sifBound)
        {
            std::cerr << "[downhill] failed to bind sceSifSendCmd at 0x0025C440\n";
        }
    }
}

PS2_REGISTER_GAME_OVERRIDE(
    "downhill-domination-ntscu-final",
    "SCUS_971.77",
    kEntryPoint,
    0u,
    applyDownhillDominationOverrides
);
