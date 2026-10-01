# Resource worker synchronization comparison

Both 180-second runs use the same Linux Release/FFmpeg executable, matching data,
and the optional idle-VBlank waits. Only the CD-read-yield flag differs.

Without the read yield, ReleaseWaitThread targets a Ready thread (status 1),
returns -416 (KE_NOT_WAIT), then the worker later enters its initial SleepThread
and the loader keeps polling. With the diagnostic read yield, the worker is
Waiting (status 2) at release, the original kernel operation returns 0, and the
worker executes its resource processing routine. This confirms the lost
initialization wait caused by the synchronous host read. Kernel ReleaseWait
semantics were not changed.

The subsequent loader still did not finish in this test. The main thread waits
on semaphore 8 around return 0x23144C; worker 10 is Running and its published
snapshot shows the memcpy entry with return 0x240BB4 in function 0x2407F8.
This is neither a validated menu nor race gameplay.

`long-probe` repeats the positive configuration for 420 seconds. Loading did not finish, and the final capture is incomplete image data rather than a menu.
