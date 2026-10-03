#include "runtime/ps2_memory.h"
#include <algorithm>
#include <array>
#include <cstdio>
#include <cstring>
#include <vector>
static void word(std::vector<uint8_t>& v,uint32_t w){const auto n=v.size();v.resize(n+4);std::memcpy(v.data()+n,&w,4);}
static void send(PS2Memory& m,unsigned u,const uint8_t* d,size_t n){if(u)m.processVIF1Data(d,static_cast<uint32_t>(n));else m.processVIF0Data(d,static_cast<uint32_t>(n));}
int main(){
 unsigned cases=0;
 for(unsigned u=2;u-->0;)for(unsigned format=0;format<16;++format){
  if((format%4==3 && format!=15)||(!u && format%4!=0))continue;
  for(unsigned count:{3u,256u})for(unsigned cycle:{0x0101u,0x0204u,0x0402u})for(unsigned mask:{0u,1u}){
   PS2Memory m;if(!m.initialize())return 1;
   auto& regs=u?m.vif1_regs:m.vif0_regs;regs.cycle=cycle;regs.mode=2;regs.mask=0xe4e4e4e4u;regs.tops=1018;
   for(unsigned i=0;i<4;++i){regs.row[i]=0x1000+i;regs.col[i]=0x2000+i;}
   const auto initial=regs;const auto capacity=u?PS2_VU1_DATA_SIZE:PS2_VU0_DATA_SIZE;auto* ram=u?m.getVU1Data():m.getVU0Data();
   const unsigned cl=cycle%256,wl=cycle/256;
   const unsigned sources=cl<wl?(count/wl)*cl+std::min(count%wl,cl):count;
   const unsigned vn=format/4,vl=format%4;
   const unsigned vectorBytes=format==15?2:(vn+1)*(vl==0?4:vl==1?2:1);
   const unsigned payload=(sources*vectorBytes+3)&~3u;
   std::vector<uint8_t> packet;word(packet,((0x60u+format+(mask?0x10u:0u))<<24)|((count%256)<<16)|0xc008u);
   for(unsigned i=0;i<payload;i+=4)word(packet,0x07000000u+i);word(packet,0x07001234u);
   std::memset(ram,0x5a,capacity);send(m,u,packet.data(),packet.size());
   const std::vector<uint8_t> expected(ram,ram+capacity);const auto expectedRegs=regs;
   for(size_t split=4;split<packet.size();split+=4){
    regs=initial;std::memset(ram,0x5a,capacity);
    send(m,u,packet.data(),split);send(m,u,packet.data()+split,packet.size()-split);
    if(std::memcmp(ram,expected.data(),capacity)||std::memcmp(regs.row,expectedRegs.row,sizeof(regs.row))||regs.mark!=0x1234u){
     std::fprintf(stderr,"UNPACK split failed VIF%u format=%u count=%u cycle=%04x mask=%u split=%zu\n",u,format,count,cycle,mask,split);return 2;
    }++cases;
   }
   regs=initial;std::memset(ram,0x5a,capacity);
   for(size_t i=0;i<packet.size();i+=16)send(m,u,packet.data()+i,std::min<size_t>(16,packet.size()-i));
   if(std::memcmp(ram,expected.data(),capacity)||regs.mark!=0x1234u)return 3;++cases;
  }
 }
 // A known V4-32 position packet independently checks the contiguous oracle.
 PS2Memory m;if(!m.initialize())return 4;std::vector<uint8_t> p;word(p,0x6c010005u);
 for(auto x:{0x3f800000u,0x40000000u,0x40400000u,0x3f800000u})word(p,x);
 send(m,1,p.data(),4);send(m,1,p.data()+4,p.size()-4);
 const std::array<uint32_t,4> xyz{0x3f800000u,0x40000000u,0x40400000u,0x3f800000u};
 if(std::memcmp(m.getVU1Data()+5*16,xyz.data(),16))return 5;
 // FBRST cancels an incomplete geometry upload.
 send(m,1,p.data(),4);m.writeIORegister(0x10003c10u,1u);const uint32_t mark=0x07005678u;
 send(m,1,reinterpret_cast<const uint8_t*>(&mark),4);if(m.vif1_regs.mark!=0x5678u)return 6;
 std::printf("VIF UNPACK: %u split/whole geometry cases plus known vertex and reset passed\n",cases);
}
