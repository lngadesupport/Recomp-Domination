#include "runtime/ps2_vif1_trace.h"
#include <iostream>
int main() {
    Vif1CommandTrace trace;
    if(trace.sequence!=0) return 1;
    for(uint32_t i=1;i<=100000;++i) {
        trace.record(0x4a000000u|i,i*4,i*16);
        const uint64_t first=i>64 ? i-63 : 1;
        for(uint64_t j=first;j<=i;++j) {
            const auto &entry=trace.entries[(j-1)%64];
            if(entry.sequence!=j || entry.code!=(0x4a000000u|j) ||
               entry.offset!=j*4 || entry.packetBytes!=j*16) return 1;
        }
    }
    trace={};if(trace.sequence!=0) return 1;
    std::cout << "PASS vif1_trace_wraparound_records=100000\n";
}
