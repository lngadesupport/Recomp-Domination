#include "game_overrides.h"
#include "downhill_leaf_handler.h"
#include "ps2_syscalls.h"
#include "ps2_runtime.h"
#include "ps2_runtime_macros.h"
#include "ps2_stubs.h"
#include "runtime/ee_scheduler.h"

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>

namespace
{
    constexpr uint32_t kEntryPoint = 0x0010A008u;
    constexpr uint32_t kExpectedFileCrc32 = 0x00000000u; // Replaced locally after ELF validation.
    constexpr uint32_t kScePadRead = 0x002451B0u;
    constexpr uint32_t kMemcpy = 0x00254050u;
    constexpr uint32_t kSceCdLayerSearchFile = 0x00246FA0u;
    constexpr uint32_t kSceSifSendCmd = 0x0025C440u;

    bool hasIsoExtension(const std::filesystem::path &path)
    {
        std::string extension = path.extension().string();
        std::transform(extension.begin(), extension.end(), extension.begin(),
                       [](unsigned char ch) { return static_cast<char>(std::tolower(ch)); });
        return extension == ".iso";
    }


    std::filesystem::path readPathSidecar(const std::filesystem::path &file)
    {
        std::ifstream stream(file);
        if (!stream)
        {
            return {};
        }

        std::string value;
        std::getline(stream, value);
        while (!value.empty() && std::isspace(static_cast<unsigned char>(value.back())))
        {
            value.pop_back();
        }

        size_t first = 0;
        while (first < value.size() && std::isspace(static_cast<unsigned char>(value[first])))
        {
            ++first;
        }
        value.erase(0, first);

        if (value.empty())
        {
            return {};
        }

        return std::filesystem::path(value);
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

        const fs::path configuredCdRoot = readPathSidecar(root / "downhill_cd_root.txt");
        const bool hasConfiguredCdRoot =
            !configuredCdRoot.empty() && fs::is_directory(configuredCdRoot, ec);
        if (hasConfiguredCdRoot)
        {
            paths.cdRoot = configuredCdRoot;
            std::cerr << "[downhill] configured CD root: " << configuredCdRoot.string() << "\n";
        }

        ec.clear();
        const fs::path configuredCdImage = readPathSidecar(root / "downhill_cd_image.txt");
        if (!configuredCdImage.empty() && fs::is_regular_file(configuredCdImage, ec))
        {
            paths.cdImage = configuredCdImage;
            std::cerr << "[downhill] configured CD image: " << configuredCdImage.string() << "\n";
        }

        // Prefer an extracted disc root when SYSTEM.CNF is directly beside the ELF.
        if (paths.cdRoot == root && fs::exists(root / "SYSTEM.CNF", ec))
        {
            paths.cdRoot = root;
        }
        else if (!hasConfiguredCdRoot)
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

    void downhillCdLayerSearchFile(uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)
    {
        const uint32_t layer = GPR_U32(ctx, 6);
        // The existing CD backend searches layer zero in an ISO or extracted
        // disc tree. Do not claim a successful lookup for unsupported layers.
        if (layer != 0u)
        {
            std::cerr << "[downhill:cd-layer-unsupported] layer=" << layer << "\n";
            SET_GPR_S32(ctx, 2, 0);
            return;
        }
        ps2_stubs::sceCdSearchFile(rdram, ctx, runtime);
    }

    PS2Runtime::RecompiledFunction originalMovieRotate = nullptr;

    void downhillIdleVSync(uint8_t *, R5900Context *, PS2Runtime *runtime)
    {
        // Diagnostic only: park the dedicated endless rotation worker at an
        // existing VBlank event. The scheduler's EE clock remains unchanged.
        runtime->eeScheduler().waitVSync(runtime->eeScheduler().currentVSyncTick(), 0,
            [](R5900Context &resumed) { resumed.pc = 0x002243C0u; });
    }

    void downhillMovieRotate(uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)
    {
        const uint32_t returnPc = GPR_U32(ctx, 31);
        uint32_t queued = 0u, capacity = 0u, state = 0u;
        std::memcpy(&queued, rdram + 0x00663B4Cu, sizeof(queued));
        std::memcpy(&capacity, rdram + 0x00663B50u, sizeof(capacity));
        std::memcpy(&state, rdram + 0x00663C00u, sizeof(state));
        const bool fullPool = returnPc == 0x0023C4E0u && capacity != 0u && queued == capacity;
        const bool finalDrain = returnPc == 0x0023C468u && queued != 0u;
        const bool shutdown = returnPc == 0x00223D78u && state == 1u;
        if (fullPool || finalDrain || shutdown)
        {
            runtime->eeScheduler().waitVSync(runtime->eeScheduler().currentVSyncTick(), 0,
                [returnPc](R5900Context &resumed) { resumed.pc = returnPc; });
        }
        originalMovieRotate(rdram, ctx, runtime);
    }

    PS2Runtime::RecompiledFunction originalResourceCdRead = nullptr;
    PS2Runtime::RecompiledFunction originalReleaseWait = nullptr;

    void downhillTraceReleaseWait(uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)
    {
        const int targetId = static_cast<int>(GPR_U32(ctx, 4));
        const uint32_t returnPc = GPR_U32(ctx, 31);
        const auto *target = runtime->eeScheduler().thread(targetId);
        const int before = target != nullptr ? static_cast<int>(target->status) : -1;
        originalReleaseWait(rdram, ctx, runtime);
        std::cerr << "[downhill:release-wait] target=" << targetId
                  << " status_before=" << before
                  << " result=" << static_cast<int32_t>(GPR_U32(ctx, 2))
                  << " return=0x" << std::hex << returnPc << std::dec << '\n';
    }

    void downhillResourceCdReadYield(uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)
    {
        const uint32_t returnPc = GPR_U32(ctx, 31);
        originalResourceCdRead(rdram, ctx, runtime);
        if (returnPc == 0x0023147Cu && GPR_U32(ctx, 2) == 1u)
        {
            // Diagnostic for the resource worker's initial SleepThread race.
            // The read still executes normally. This is not a DVD latency model.
            std::cerr << "[downhill:cd-read-yield] return=0x23147c\n";
            runtime->eeScheduler().waitVSync(runtime->eeScheduler().currentVSyncTick(), 1,
                [returnPc](R5900Context &resumed) { resumed.pc = returnPc; });
        }
    }

    // Only accessed by the guest executor. Reset when applying this game's overrides.
    uint64_t resourceCopyCalls = 0, resourceZeroCopies = 0;

    std::string resourceByteSample(const uint8_t *rdram, uint32_t address, uint32_t length)
    {
        // Diagnostic reads use the same translation as the existing memcpy stub.
        // Resolve each byte separately so samples never cross a host allocation.
        std::ostringstream sample;
        constexpr char hex[] = "0123456789abcdef";
        for (uint32_t i = 0; i < std::min(length, 16u); ++i)
        {
            const uint8_t *byte = getConstMemPtr(rdram, address + i);
            if (byte == nullptr) break;
            sample << hex[*byte >> 4] << hex[*byte & 15u];
        }
        return sample.str();
    }

    void downhillTraceResourceCopy(uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)
    {
        if (GPR_U32(ctx, 31) != 0x00240BB4u)
        {
            downhill::leafHandler<ps2_stubs::memcpy>(rdram, ctx, runtime);
            return;
        }
        const uint32_t source = GPR_U32(ctx, 5), destination = GPR_U32(ctx, 4);
        const uint32_t length = GPR_U32(ctx, 6);
        const uint64_t call = ++resourceCopyCalls;
        resourceZeroCopies += length == 0u;
        // Bounded output even if a guest loop repeats billions of zero-size calls.
        const bool emit = call <= 64u || (call & (call - 1u)) == 0u;
        std::string sourceBytes;
        if (emit) sourceBytes = resourceByteSample(rdram, source, length);
        downhill::leafHandler<ps2_stubs::memcpy>(rdram, ctx, runtime);
        if (!emit) return;
        std::ostringstream line;
        line << "[downhill:resource-copy] call=" << call
             << " zero_calls=" << resourceZeroCopies
             << " thread=" << runtime->eeScheduler().currentThreadId()
             << " length=" << length
             << " source=" << source << " destination=" << destination
             << " input_offset=" << GPR_U32(ctx, 17)
             // The JAL delay slot has already incremented s5 by s0.
             << " output_after=" << GPR_U32(ctx, 21)
             << " remaining_after=" << GPR_U32(ctx, 22)
             << " window=" << GPR_U32(ctx, 30)
             << " input_base=" << Ps2FastRead32(rdram, 0x0029E468u)
             << " output_base=" << Ps2FastRead32(rdram, 0x0029E48Cu)
             << " source_bytes=" << sourceBytes
             << " destination_bytes=" << resourceByteSample(rdram, destination, length)
             << " result=" << GPR_U32(ctx, 2) << '\n';
        std::cerr << line.str();
    }

    PS2Runtime::RecompiledFunction originalDmaQueueWait = nullptr;

    PS2Runtime::RecompiledFunction originalResourceReturn = nullptr;
    PS2Runtime::RecompiledFunction originalResourceCaller = nullptr;
    PS2Runtime::RecompiledFunction originalResourceParent = nullptr;
    PS2Runtime::RecompiledFunction originalResourceChild = nullptr;
    uint64_t resourceParentCalls = 0, resourceParentAnomalies = 0;
    uint64_t resourceChildCalls = 0, resourceChildAnomalies = 0;
    uint64_t resourceReturnCalls = 0, resourceReturnAnomalies = 0;
    uint64_t resourceCallerCalls = 0, resourceCallerAnomalies = 0;
    void traceResourceFrame(uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime,
                            PS2Runtime::RecompiledFunction original, uint32_t base, uint32_t size,
                            uint32_t raOffset, uint64_t &calls, uint64_t &anomalies)
    {
        const uint32_t entryPc = ctx->pc, entrySp = GPR_U32(ctx, 29), entryRa = GPR_U32(ctx, 31);
        const uint32_t frame = entryPc == base ? entrySp - size : entrySp;
        const uint32_t savedBefore = Ps2FastRead32(rdram, frame + raOffset);
        const uint32_t entryA0 = GPR_U32(ctx, 4), entryA1 = GPR_U32(ctx, 5);
        const uint32_t expectedSp = frame + size;
        const uint32_t expectedRa = entryPc == base ? entryRa : savedBefore;
        const uint64_t call = ++calls;
        original(rdram, ctx, runtime);
        const uint32_t savedAfter = Ps2FastRead32(rdram, frame + raOffset);
        const bool invalidTarget = ctx->pc != 0u && !runtime->hasFunction(ctx->pc);
        const bool invalidSaved = savedAfter != 0u && !runtime->hasFunction(savedAfter);
        const bool stackMismatch = ctx->pc == expectedRa && GPR_U32(ctx, 29) != expectedSp;
        const uint64_t anomaly = (invalidTarget || invalidSaved || stackMismatch) ? ++anomalies : 0u;
        const bool sample = call <= 16u || (call & (call - 1u)) == 0u;
        const bool sampleAnomaly = anomaly && (anomaly <= 32u || (anomaly & (anomaly - 1u)) == 0u);
        if (!sample && !sampleAnomaly) return;
        std::ostringstream line;
        line << "[downhill:resource-return] call=" << call << " anomaly=" << anomaly
             << " thread=" << runtime->eeScheduler().currentThreadId()
             << std::hex << " routine=0x" << base << " entry_pc=0x" << entryPc << " entry_sp=0x" << entrySp
             << " entry_ra=0x" << entryRa << " frame=0x" << frame
             << " a0=0x" << entryA0 << " a1=0x" << entryA1
             << " expected_sp=0x" << expectedSp << " expected_ra=0x" << expectedRa
             << " saved_before=0x" << savedBefore << " saved_after=0x" << savedAfter
             << " exit_pc=0x" << ctx->pc << " exit_ra=0x" << GPR_U32(ctx, 31)
             << " exit_sp=0x" << GPR_U32(ctx, 29) << " branch_pc=0x" << ctx->branch_pc << std::dec << '\n';
        std::cerr << line.str();
    }

    void downhillTraceResourceReturn(uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)
    {
        traceResourceFrame(rdram, ctx, runtime, originalResourceReturn, 0x00203D18u, 32u, 16u,
                           resourceReturnCalls, resourceReturnAnomalies);
    }
    void downhillTraceResourceCaller(uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)
    {
        traceResourceFrame(rdram, ctx, runtime, originalResourceCaller, 0x00205F40u, 64u, 48u,
                           resourceCallerCalls, resourceCallerAnomalies);
    }

    void downhillTraceResourceParent(uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)
    {
        traceResourceFrame(rdram, ctx, runtime, originalResourceParent, 0x00204C40u, 16u, 0u,
                           resourceParentCalls, resourceParentAnomalies);
    }
    void downhillTraceResourceChild(uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)
    {
        traceResourceFrame(rdram, ctx, runtime, originalResourceChild, 0x00204CE0u, 16u, 0u,
                           resourceChildCalls, resourceChildAnomalies);
    }

    PS2Runtime::RecompiledFunction originalFrameWait = nullptr;
    PS2Runtime::RecompiledFunction originalNumericDisplay = nullptr;
    uint64_t frameStateCalls = 0, numericDisplayCalls = 0;
    uint64_t numericDisplayAnomalies = 0;

    void downhillTraceFrameState(uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)
    {
        const uint32_t entryPc = ctx->pc, entrySp = GPR_U32(ctx, 29);
        const uint32_t frame = entryPc == 0x00238C00u ? entrySp - 32u : entrySp;
        const uint32_t caller = entryPc == 0x00238C00u ? GPR_U32(ctx, 31)
            : Ps2FastRead32(rdram, frame + 24u);
        const uint64_t call = ++frameStateCalls;
        originalFrameWait(rdram, ctx, runtime);
        // These are executor-thread observations. A Ready snapshot at this
        // continuation alone cannot establish either a stall or a game mode.
        if (call > 4u && call % 120u != 0u) return;
        if (call > 61440u) return; // At most 516 records per initialized run.
        std::ostringstream line;
        line << "[downhill:frame-state] call=" << call
             << " vsync=" << runtime->eeScheduler().currentVSyncTick()
             << " numeric_calls=" << numericDisplayCalls
             << std::hex << " entry_pc=0x" << entryPc << " caller=0x" << caller
             << " frame=0x" << frame << " exit_pc=0x" << ctx->pc
             << " exit_sp=0x" << GPR_U32(ctx, 29) << " stack=";
        for (uint32_t i = 0; i < 32u; ++i)
            line << Ps2FastRead32(rdram, frame + i * 4u) << ',';
        line << " gpr=";
        for (uint32_t i = 0; i < 32u; ++i) line << GPR_U32(ctx, i) << ',';
        line << std::dec << '\n';
        std::cerr << line.str();
    }

    void downhillTraceNumericDisplay(uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)
    {
        traceResourceFrame(rdram, ctx, runtime, originalNumericDisplay,
            0x00177DA0u, 48u, 32u, numericDisplayCalls, numericDisplayAnomalies);
    }

    uint64_t dmaWaitCalls = 0;
    void downhillTraceDmaQueueWait(uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)
    {
        originalDmaQueueWait(rdram, ctx, runtime);
        const uint64_t call = ++dmaWaitCalls;
        if (call <= 16u || (call & (call - 1u)) == 0u)
            std::cerr << "[downhill:dma-wait] call=" << call
                      << " pc=" << ctx->pc << " ra=" << GPR_U32(ctx, 31)
                      << " flags=" << Ps2FastRead32(rdram, 0x0029E1C8u) << ','
                      << Ps2FastRead32(rdram, 0x0029E1CCu) << ','
                      << Ps2FastRead32(rdram, 0x0029E1E4u)
                      << " chcr=" << runtime->memory().readIORegister(0x10009000u)
                      << " qwc=" << runtime->memory().readIORegister(0x10009020u)
                      << " tadr=" << runtime->memory().readIORegister(0x10009030u)
                      << " dstat=" << runtime->memory().readIORegister(0x1000E010u)
                      << " cop0=" << ctx->cop0_status << '\n';
    }

    void applyDownhillDominationOverrides(PS2Runtime &runtime)
    {
        configureDownhillIoPaths();
        const char *frameTrace = std::getenv("PS2_TRACE_DOWNHILL_FRAME_STATE");
        if (frameTrace && std::strcmp(frameTrace, "1") == 0)
        {
            originalFrameWait = runtime.lookupFunction(0x00238C00u);
            originalNumericDisplay = runtime.lookupFunction(0x00177DA0u);
            frameStateCalls = numericDisplayCalls = numericDisplayAnomalies = 0;
            if (originalFrameWait)
                for (const uint32_t pc : {0x00238C00u, 0x00238C50u, 0x00238C64u, 0x00238C70u})
                    runtime.replaceFunction(pc, downhillTraceFrameState);
            if (originalNumericDisplay)
                for (const uint32_t pc : {0x00177DA0u, 0x00177E68u, 0x00177E78u})
                    runtime.replaceFunction(pc, downhillTraceNumericDisplay);
            std::cerr << "[downhill] frame state diagnostics wait=" << bool(originalFrameWait)
                      << " numeric=" << bool(originalNumericDisplay) << '\n';
        }
        const char *returnTrace = std::getenv("PS2_TRACE_DOWNHILL_RESOURCE_RETURN");
        if (returnTrace && std::strcmp(returnTrace, "1") == 0)
        {
            originalResourceParent = runtime.lookupFunction(0x00204C40u);
            originalResourceChild = runtime.lookupFunction(0x00204CE0u);
            resourceParentCalls = resourceParentAnomalies = 0;
            resourceChildCalls = resourceChildAnomalies = 0;
            if (originalResourceParent)
                for (const uint32_t pc : {0x00204C40u, 0x00204C9Cu, 0x00204CD0u})
                    runtime.replaceFunction(pc, downhillTraceResourceParent);
            if (originalResourceChild)
                for (const uint32_t pc : {0x00204CE0u, 0x00204D3Cu, 0x00204D50u, 0x00204DB8u,
                                          0x00204DCCu, 0x00204DE0u, 0x00204DF4u, 0x00204E08u, 0x00204E1Cu})
                    runtime.replaceFunction(pc, downhillTraceResourceChild);
            originalResourceReturn = runtime.lookupFunction(0x00203D18u);
            resourceReturnCalls = resourceReturnAnomalies = 0;
            originalResourceCaller = runtime.lookupFunction(0x00205F40u);
            resourceCallerCalls = resourceCallerAnomalies = 0;
            if (originalResourceReturn)
                for (const uint32_t pc : {0x00203D18u, 0x00203D9Cu, 0x00203DACu, 0x00203DBCu})
                    runtime.replaceFunction(pc, downhillTraceResourceReturn);
            if (originalResourceCaller)
                for (const uint32_t pc : {0x00205F40u, 0x00206020u, 0x00206058u, 0x00206110u, 0x002061B0u})
                    runtime.replaceFunction(pc, downhillTraceResourceCaller);
        }
        const char *dmaTrace = std::getenv("PS2_TRACE_DMAC_IRQ");
        if (dmaTrace != nullptr && std::strcmp(dmaTrace, "1") == 0)
        {
            originalDmaQueueWait = runtime.lookupFunction(0x001B4618u);
            dmaWaitCalls = 0;
            if (originalDmaQueueWait != nullptr)
            {
                runtime.replaceFunction(0x001B4618u, downhillTraceDmaQueueWait);
                runtime.replaceFunction(0x001B4648u, downhillTraceDmaQueueWait);
            }
        }

        const char *idleVSync = std::getenv("PS2_DOWNHILL_IDLE_VSYNC");
        if (idleVSync != nullptr && std::strcmp(idleVSync, "1") == 0)
        {
            originalMovieRotate = runtime.lookupFunction(0x00224058u);
            if (originalMovieRotate != nullptr &&
                runtime.replaceFunction(0x002243C0u, downhillIdleVSync) &&
                runtime.replaceFunction(0x00224058u, downhillMovieRotate))
                std::cerr << "[downhill] experimental idle VSync waits enabled\n";
            else
                std::cerr << "[downhill] experimental idle VSync binding failed\n";
        }

        if (std::getenv("PS2_TRACE_BOOT_SNAPSHOT") != nullptr)
        {
            originalReleaseWait = runtime.lookupFunction(0x0025A5B0u);
            if (originalReleaseWait != nullptr)
                runtime.replaceFunction(0x0025A5B0u, downhillTraceReleaseWait);
        }
        const char *readYield = std::getenv("PS2_DOWNHILL_CD_READ_YIELD");
        if (readYield != nullptr && std::strcmp(readYield, "1") == 0)
        {
            originalResourceCdRead = runtime.lookupFunction(0x00247D28u);
            if (originalResourceCdRead != nullptr &&
                runtime.replaceFunction(0x00247D28u, downhillResourceCdReadYield))
                std::cerr << "[downhill] experimental resource CD read yield enabled\n";
        }

        const bool padBound =
            runtime.replaceFunction(kScePadRead, downhill::leafHandler<ps2_stubs::scePadRead>);

        const bool sifBound =
            runtime.replaceFunction(kSceSifSendCmd, downhill::leafHandler<ps2_syscalls::sceSifSendCmd>);
        const bool mpegEndBound =
            runtime.replaceFunction(0x0024D1C0u, downhill::leafHandler<ps2_stubs::sceMpegIsEnd>);
        const bool mpegEmptyBound =
            runtime.replaceFunction(0x0024D1D0u, downhill::leafHandler<ps2_stubs::sceMpegIsRefBuffEmpty>);
        const bool memcpyBound =
            runtime.replaceFunction(kMemcpy, downhill::leafHandler<ps2_stubs::memcpy>);
        const char *resourceTrace = std::getenv("PS2_TRACE_RESOURCE_COPY");
        if (memcpyBound && resourceTrace != nullptr && std::strcmp(resourceTrace, "1") == 0)
        {
            resourceCopyCalls = resourceZeroCopies = 0;
            if (runtime.replaceFunction(kMemcpy, downhillTraceResourceCopy))
                std::cerr << "[downhill] bounded resource copy diagnostics enabled\n";
        }
        const bool cdSearchBound =
            runtime.registerFunction(kSceCdLayerSearchFile, downhill::leafHandler<downhillCdLayerSearchFile>);

        if (!padBound)
        {
            std::cerr << "[downhill] failed to bind scePadRead at 0x002451B0\n";
        }

        if (!sifBound)
        {
            std::cerr << "[downhill] failed to bind sceSifSendCmd at 0x0025C440\n";
        }
        if (!mpegEndBound || !mpegEmptyBound)
        {
            std::cerr << "[downhill] failed to bind MPEG state queries\n";
        }
        if (!memcpyBound || !cdSearchBound)
        {
            std::cerr << "[downhill] failed to bind memcpy or sceCdLayerSearchFile\n";
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
