#include "printf.h"
#include "mini_uart.h"
#include "mem.h"
#include "timer.h"
#include "peripherals/timer.h"
#include <circle/timer.h>

#ifdef __cplusplus
extern "C"
{
#endif

static u64 initialTicks;

void timer_init()
{
}

u64 timer_get_ticks()
{
	return CTimer::Get()->GetClockTicks();
}

// Sleep for ticks microseconds
void timer_sleep_ticks(u64 sleep_ticks)
{
	CTimer::Get()->usDelay((u32)sleep_ticks);
}

// Sleep for ticks milliseconds
void timer_sleep_ms(u64 sleep_ms)
{
	timer_sleep_ticks(sleep_ms * 1000);
}

u64 timer_get_millis()
{
	u64 curTicks = timer_get_ticks();
	return (curTicks - initialTicks) / 1000;
}

#ifdef __cplusplus
}
#endif
