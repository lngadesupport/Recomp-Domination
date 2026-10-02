#include "runtime/gs/gs_cpu_backend.h"
#include <cstdio>
#include <vector>

int main()
{
    std::vector<uint8_t> vram(4u * 1024u * 1024u);
    GSCpuBackend backend;
    backend.Initialize(vram.data(), static_cast<uint32_t>(vram.size()));
    backend.WriteVram(GS_PSM_CT32, 8800, 1, 0, 0, 0x80402010u);
    GSPrimitiveBatch batch{};
    batch.vertexCount = 3;
    auto &state = batch.state;
    state.prim.type = GS_PRIM_TRIANGLE;
    state.prim.tme = state.prim.fst = true;
    state.textureWidth = state.textureHeight = 1;
    state.context.tex0.tbp0 = 8800;
    state.context.tex0.tbw = 1;
    state.context.tex0.psm = GS_PSM_CT32;
    state.context.tex0.tcc = 1;
    state.context.tex0.tfx = 1;
    state.context.frame.fbp = 4;
    state.context.frame.fbw = 1;
    state.context.frame.psm = GS_PSM_CT32;
    state.context.test = 1u << 17;
    state.context.zbuf.zmask = true;
    state.context.scissor.x1 = state.context.scissor.y1 = 7;
    batch.vertices[0].x = batch.vertices[0].y = 1;
    batch.vertices[1].x = 6; batch.vertices[1].y = 1;
    batch.vertices[2].x = 1; batch.vertices[2].y = 6;
    for (auto &vertex : batch.vertices) vertex.r = vertex.g = vertex.b = vertex.a = 128;
    for (unsigned n = 0; n < 3; ++n) backend.Submit(batch);
    // Texture replacement independently anchors the pixel output, with trace on or off.
    if (backend.ReadVram(GS_PSM_CT32, 128, 1, 2, 2) != 0x80402010u) return 1;
    if (backend.ReadVram(GS_PSM_CT32, 128, 1, 6, 6) != 0) return 2;
    std::puts("Triangle trace preserves textured raster output");
}
