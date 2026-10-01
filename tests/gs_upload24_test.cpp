#include "runtime/gs/gs_cpu_backend.h"
#include <algorithm>
#include <cstdio>
#include <vector>

int main()
{
    std::vector<uint8_t> vram(4 * 1024 * 1024);
    GSCpuBackend backend;
    backend.Initialize(vram.data(), static_cast<uint32_t>(vram.size()));
    unsigned cases = 0;
    for (const uint8_t psm : {uint8_t(GS_PSM_CT24), uint8_t(GS_PSM_Z24)})
    {
        const uint8_t fullPsm = psm == GS_PSM_CT24 ? GS_PSM_CT32 : GS_PSM_Z32;
        for (unsigned ordinal = 1; ordinal <= 80; ++ordinal)
        {
            const unsigned chunk = ordinal == 1 ? 16 : ordinal == 16 ? 1 : ordinal;
            backend.Reset();
            GSTransferCommand command{};
            command.direction = 0;
            command.bitbltbuf.dbp = 64;
            command.bitbltbuf.dbw = 2;
            command.bitbltbuf.dpsm = psm;
            command.trxpos.dsax = 61;
            command.trxpos.dsay = 29;
            command.trxreg.rrw = 11;
            command.trxreg.rrh = 2;
            std::vector<uint8_t> bytes(80, 0);
            for (unsigned pixel = 0; pixel < 22; ++pixel)
            {
                bytes[pixel * 3] = static_cast<uint8_t>(pixel + 1);
                bytes[pixel * 3 + 1] = static_cast<uint8_t>(pixel + 31);
                bytes[pixel * 3 + 2] = static_cast<uint8_t>(pixel + 91);
                backend.WriteVram(fullPsm, 64, 2, 61 + pixel % 11, 29 + pixel / 11, 0xaa000000);
            }
            backend.BeginTransfer(command);
            backend.WriteVram(fullPsm, 64, 2, 61, 31, 0xaaabcdef);
            for (unsigned offset = 0; offset < bytes.size(); offset += chunk)
                backend.UploadImage(bytes.data() + offset, std::min<unsigned>(chunk, bytes.size() - offset));
            for (unsigned pixel = 0; pixel < 22; ++pixel)
            {
                const uint32_t expected = 0xaa000000u | bytes[pixel * 3] |
                    (uint32_t(bytes[pixel * 3 + 1]) << 8) | (uint32_t(bytes[pixel * 3 + 2]) << 16);
                const uint32_t actual = backend.ReadVram(fullPsm, 64, 2, 61 + pixel % 11, 29 + pixel / 11);
                if (actual != expected)
                {
                    std::fprintf(stderr, "PSM=%u chunk=%u pixel=%u actual=%08x expected=%08x\n", psm, chunk, pixel, actual, expected);
                    return 1;
                }
            }
            const auto snapshot = backend.GetTransferSnapshot();
            if (snapshot.copiedPixels != 22 || snapshot.direction != 3)
                return 2;
            if (backend.ReadVram(fullPsm, 64, 2, 61, 31) != 0xaaabcdef)
                return 3;
            ++cases;
        }
        for (unsigned pending = 1; pending <= 2; ++pending)
        {
            for (bool reset : {false, true})
            {
                GSTransferCommand command{};
                command.direction = 0;
                command.bitbltbuf.dbp = 64;
                command.bitbltbuf.dbw = 1;
                command.bitbltbuf.dpsm = psm;
                command.trxreg.rrw = command.trxreg.rrh = 1;
                const uint8_t abandoned[] = {0xee, 0xdd};
                const uint8_t replacement[] = {0x12, 0x34, 0x56};
                backend.BeginTransfer(command);
                backend.UploadImage(abandoned, pending);
                if (reset)
                    backend.Reset();
                backend.BeginTransfer(command);
                backend.UploadImage(replacement, 1);
                backend.UploadImage(nullptr, 10);
                backend.UploadImage(replacement, 0);
                backend.UploadImage(replacement + 1, 2);
                if (backend.ReadVram(psm, 64, 1, 0, 0) != 0x563412)
                    return 4;
                ++cases;
            }
        }
    }
    std::printf("24-bit upload: %u cases passed (chunk boundaries, padding, cancellation, reset, empty calls)\n", cases);
}
