#include "runtime/gs/gs_cpu_backend.h"
#include <vector>
#include <cstdio>
int main() {
 std::vector<uint8_t> vram(4*1024*1024); GSCpuBackend backend; backend.Initialize(vram.data(), vram.size());
 GSTex0Reg tex{}; tex.psm=GS_PSM_T4; tex.tbp0=0; tex.tbw=1; tex.cbp=32; tex.cpsm=GS_PSM_CT32; tex.cld=1; tex.tcc=1; tex.tfx=1;
 backend.WriteVram(GS_PSM_CT32,32,1,0,0,0x8000ff00); backend.LoadClut(tex,{});
 backend.WriteVram(GS_PSM_CT32,32,1,0,0,0x800000ff); backend.LoadClut(tex,{});
 GSPrimitiveBatch batch{}; batch.vertexCount=2; batch.state.prim.type=GS_PRIM_SPRITE; batch.state.prim.tme=true; batch.state.prim.fst=true;
 batch.state.context.test=1u<<17; batch.state.context.tex0=tex; batch.state.context.frame.fbp=4; batch.state.context.frame.fbw=1; batch.state.context.frame.psm=GS_PSM_CT32;
 batch.state.context.scissor.x1=1; batch.state.context.scissor.y1=1; batch.state.context.zbuf.zmask=true;
 batch.vertices[1].x=1; batch.vertices[1].y=1;
 for(auto &v:batch.vertices) v.r=v.g=v.b=v.a=128;
 backend.Submit(batch); auto pixel=backend.ReadVram(GS_PSM_CT32,128,1,0,0);
 std::printf("CLD=1 reload pixel=%08x expected RGB=0000ff\n",pixel); return (pixel&0xffffff)==0xff ? 0:1;
}
