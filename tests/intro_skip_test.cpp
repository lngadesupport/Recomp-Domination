#include "runtime/ps2_intro_skip.h"
#include <cassert>
int main() {
 PS2IntroSkip s; assert(!s.start(0)); s.frame(1000);
 assert(s.start(1000)); assert(s.start(1199)); assert(!s.start(1200));
 assert(!s.start(2000)); s.frame(2000); assert(s.start(2000));
 assert(!s.start(2301)); assert(!s.start(999));
 s.frame(13000); assert(!s.start(13000));
 s.reset(); assert(!s.start(13000)); s.frame(14000); assert(s.start(14000));
}
