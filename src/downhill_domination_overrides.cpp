#include "game_overrides.h"
#include "ps2_runtime.h"

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <filesystem>
#include <iostream>
#include <string>

namespace
{
    constexpr uint32_t kEntryPoint = 0x0010A008u;
    constexpr uint32_t kExpectedFileCrc32 = 0x00000000u; // Replaced locally after ELF validation.
    constexpr uint32_t kScePadRead = 0x00254050u;
    constexpr uint32_t kSceSifSendCmd = 0x0025C440u;

    bool hasIsoExtension(const std::filesystem::path &path)
    {
        std::string extension = path.extension().string();
        std::transform(extension.begin(), extension.end(), extension.begin(),
                       [](unsigned char ch) { return static_cast<char>(std::tolower(ch)); });
        return extension == ".iso";
    }

    void configureDownhillIoPaths()
    {
        namespace fs = std::filesystem;

        PS2Runtime::IoPaths paths = PS2Runtime::getIoPaths();
        if (paths.elfDirectory.empty())
        {
            return;
        }

        std::error_code ec;
        const fs::path root = paths.elfDirectory;

        // Prefer an extracted disc root when SYSTEM.CNF is directly beside the ELF.
        if (fs::exists(root / "SYSTEM.CNF", ec))
        {
            paths.cdRoot = root;
        }
        else
        {
            // Also support a one-level extracted-disc directory under the game root.
            for (fs::directory_iterator it(root, ec), end; !ec && it != end; it.increment(ec))
            {
                if (!it->is_directory(ec))
                {
                    continue;
                }

                const fs::path candidate = it->path();
                if (fs::exists(candidate / "SYSTEM.CNF", ec))
                {
                    paths.cdRoot = candidate;
                    std::cerr << "[downhill] CD root: " << candidate.string() << "\n";
                    break;
                }
            }
        }

        // Raw sector reads can use a local ISO when one is present.
        if (paths.cdImage.empty())
        {
            ec.clear();
            for (fs::directory_iterator it(root, ec), end; !ec && it != end; it.increment(ec))
            {
                if (it->is_regular_file(ec) && hasIsoExtension(it->path()))
                {
                    paths.cdImage = it->path();
                    std::cerr << "[downhill] CD image: " << paths.cdImage.string() << "\n";
                    break;
                }
            }
        }

        PS2Runtime::setIoPaths(paths);
    }

    void applyDownhillDominationOverrides(PS2Runtime &runtime)
    {
        configureDownhillIoPaths();

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
    kExpectedFileCrc32,
    applyDownhillDominationOverrides
);
