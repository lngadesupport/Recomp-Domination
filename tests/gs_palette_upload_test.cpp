#include "runtime/gs/gs_cpu_backend.h"
#include <algorithm>
#include <array>
#include <cstdio>
#include <cstring>
#include <vector>

int main()
{
    std::vector<uint8_t> vram(4 * 1024 * 1024);
    GSCpuBackend backend;
    backend.Initialize(vram.data(), static_cast<uint32_t>(vram.size()));
    unsigned cases = 0;
    for (const uint32_t base : {4872u, 6753u, 6805u, 16383u})
    for (const bool alias : {false, true})
    for (const uint8_t psm : {uint8_t(GS_PSM_T4), uint8_t(GS_PSM_T4HL), uint8_t(GS_PSM_T4HH)})
    for (const uint32_t chunk : {16u, 32u, 64u})
    {
        backend.Reset();
        GSTex0Reg tex{};
        tex.tbp0 = 64; tex.tbw = 1; tex.psm = psm;
        tex.cbp = base; tex.cpsm = GS_PSM_CT32; tex.cld = 1;
        tex.tcc = 1; tex.tfx = 1;
        backend.LoadClut(tex, {}); // Empty palette, then actual host upload.
        std::array<uint32_t, 16> colors{};
        for (unsigned i = 0; i < colors.size(); ++i)
            colors[i] = 0x80000000u | (i + 1u) | ((i + 33u) << 8u) | ((i + 65u) << 16u);
        GSTransferCommand upload{};
        upload.direction = 0;
        upload.bitbltbuf.dbp = base - unsigned(alias);
        upload.bitbltbuf.dbw = 1; upload.bitbltbuf.dpsm = GS_PSM_CT32;
        upload.trxpos.dsax = alias ? 8 : 0;
        upload.trxreg.rrw = 8; upload.trxreg.rrh = 2;
        backend.BeginTransfer(upload);
        const auto* bytes = reinterpret_cast<const uint8_t*>(colors.data());
        for (uint32_t offset = 0; offset < sizeof(colors); offset += chunk)
            backend.UploadImage(bytes + offset, std::min<uint32_t>(chunk, sizeof(colors) - offset));
        // Independent physical offsets for the first two CT32 pixels.
        uint32_t raw[2]{};
        std::memcpy(raw, vram.data() + base * 256u, sizeof(raw));
        if (raw[0] != colors[0] || raw[1] != colors[1]) return 1;
        backend.LoadClut(tex, {});
        GSPrimitiveBatch batch{};
        batch.vertexCount = 2;
        batch.state.prim.type = GS_PRIM_SPRITE;
        batch.state.prim.tme = batch.state.prim.fst = true;
        batch.state.context.tex0 = tex;
        batch.state.context.frame.fbp = 4; batch.state.context.frame.fbw = 1;
        batch.state.context.frame.psm = GS_PSM_CT32;
        batch.state.context.test = 1u << 17;
        batch.state.context.zbuf.zmask = true;
        batch.state.context.scissor.x1 = batch.state.context.scissor.y1 = 1;
        batch.vertices[1].x = batch.vertices[1].y = 1;
        for (auto& vertex : batch.vertices) vertex.r = vertex.g = vertex.b = vertex.a = 128;
        for (unsigned index = 0; index < colors.size(); ++index)
        {
            backend.WriteVram(psm, 64, 1, 0, 0, index);
            backend.TextureFlush();
            backend.Submit(batch);
            const auto actual = backend.ReadVram(GS_PSM_CT32, 128, 1, 0, 0);
            if (actual != colors[index])
            {
                std::fprintf(stderr, "Palette upload base=%u alias=%u psm=%u chunk=%u index=%u actual=%08x expected=%08x\n",
                             base, alias, psm, chunk, index, actual, colors[index]);
                return 2;
            }
        }
        ++cases;
    }
    std::printf("Palette upload: %u cases passed (physical readback, all 16 indices, aliased bases, IMAGE chunks)\n", cases);
}
