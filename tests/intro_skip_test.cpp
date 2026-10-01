#include "runtime/ps2_intro_skip.h"
#include <cassert>
int main() {
 PS2IntroSkip s; assert(!s.start(0)); s.frame(1000);
 assert(s.start(1000)); assert(s.start(1199)); assert(!s.start(1200));
 assert(!s.start(2000)); s.frame(2000); assert(s.start(2000));
 assert(!s.start(2301)); assert(!s.start(999));
 s.frame(13000); assert(!s.start(13000));
 // Exhaustive timestamps around a running movie with delivered frames every 40ms.
 s.reset();
 for (int64_t t = 0; t < 1000000; ++t) {
  if (t < 15000 && t % 40 == 0) s.frame(t);
  const bool expected = t < 12000 && t % 1000 < 200;
  assert(s.start(t) == expected);
 }
 s.reset(); assert(!s.start(13000)); s.frame(14000); assert(s.start(14000));
}
