#include "runtime/gs/gs_cpu_backend.h"
#include <cstdio>
#include <vector>

int main()
{
    std::vector<uint8_t> vram(4 * 1024 * 1024);
    GSCpuBackend backend;
    backend.Initialize(vram.data(), static_cast<uint32_t>(vram.size()));
    unsigned cases = 0;
    for (const uint8_t psm : {uint8_t(GS_PSM_T4), uint8_t(GS_PSM_T4HL), uint8_t(GS_PSM_T4HH), uint8_t(GS_PSM_T8), uint8_t(GS_PSM_T8H)})
    for (const uint8_t cpsm : {uint8_t(GS_PSM_CT32), uint8_t(GS_PSM_CT16)})
    for (const uint8_t csm : {uint8_t(0), uint8_t(1)})
    {
        backend.Reset();
        GSTex0Reg tex{};
        tex.psm = psm; tex.tbw = 1; tex.cbp = 32;
        tex.cpsm = cpsm; tex.csm = csm; tex.cld = 1;
        tex.tcc = 1; tex.tfx = 1;
        const uint32_t green = cpsm == GS_PSM_CT32 ? 0x8000ff00 : 0x83e0;
        const uint32_t red = cpsm == GS_PSM_CT32 ? 0x800000ff : 0x801f;
        backend.WriteVram(cpsm, 32, 1, 0, 0, green);
        backend.LoadClut(tex, {});
        backend.WriteVram(cpsm, 32, 1, 0, 0, red);
        backend.LoadClut(tex, {});
        GSPrimitiveBatch batch{};
        batch.vertexCount = 2;
        batch.state.prim.type = GS_PRIM_SPRITE;
        batch.state.prim.tme = batch.state.prim.fst = true;
        batch.state.texa.ta0 = batch.state.texa.ta1 = 128;
        batch.state.context.test = 1u << 17;
        batch.state.context.tex0 = tex;
        batch.state.context.frame.fbp = 4;
        batch.state.context.frame.fbw = 1;
        batch.state.context.frame.psm = GS_PSM_CT32;
        batch.state.context.scissor.x1 = batch.state.context.scissor.y1 = 1;
        batch.state.context.zbuf.zmask = true;
        batch.vertices[1].x = batch.vertices[1].y = 1;
        for (auto &v : batch.vertices)
            v.r = v.g = v.b = v.a = 128;
        auto check = [&](uint32_t expected) {
            backend.Submit(batch);
            const uint32_t pixel = backend.ReadVram(GS_PSM_CT32, 128, 1, 0, 0);
            if (pixel != expected)
                std::fprintf(stderr, "CLUT PSM=%u CPSM=%u CSM=%u actual=%08x expected=%08x\n", psm, cpsm, csm, pixel, expected);
            return pixel == expected;
        };
        const uint32_t redRgba = cpsm == GS_PSM_CT32 ? 0x800000ff : 0x800000f8;
        const uint32_t greenRgba = cpsm == GS_PSM_CT32 ? 0x8000ff00 : 0x8000f800;
        if (!check(redRgba)) return 1;
        backend.WriteVram(cpsm, 32, 1, 0, 0, green);
        tex.cld = 0;
        backend.LoadClut(tex, {});
        if (!check(redRgba)) return 2; // CLD=0 retains the loaded palette.
        tex.cld = 1;
        backend.LoadClut(tex, {});
        if (!check(greenRgba)) return 3;
        ++cases;
    }
    std::printf("CLUT: %u format/mode cases passed (forced reload and CLD=0 retention)\n", cases);
}
