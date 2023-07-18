#include "printf.h"
#include "peripherals/timer.h"
#include "peripherals/irq.h"
#include "peripherals/aux.h"
#include "mini_uart.h"
#include "mem.h"
#include "timer.h"

#ifdef __cplusplus
extern "C"
{
#endif

#define	MAX_TIMER_CBS		10
#define TIMER_CALLBACK_HZ

static u64 initialTicks;

static timer_callback	timer_callbacks[MAX_TIMER_CBS];
static i32				num_timer_callbacks;

void timer_init()
{
	initialTicks = timer_get_ticks();
	num_timer_callbacks = 0;
	memzero(timer_callbacks, sizeof(timer_callbacks));
}

u64 timer_get_ticks()
{
	u32 hiVal = TIMER_REGS->CounterHigh;
	u32 lowVal = TIMER_REGS->CounterLow;

	// Double check that we have a correct reading of the high word - without this loop, it would be possible for a reading of CounterHigh to differ across
	// the reading of CounterLow,
	while (TIMER_REGS->CounterHigh != hiVal)
	{
		hiVal = TIMER_REGS->CounterHigh;
		lowVal = TIMER_REGS->CounterLow;
	}

	return ((u64)hiVal << 32) | lowVal;
}

// Sleep for ticks microseconds
void timer_sleep_ticks(u64 sleep_ticks)
{
	u64 destTime = timer_get_ticks() + sleep_ticks;

	while (timer_get_ticks() < destTime)
	{
		// Do nothing
	}
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

void timer_register_callback(const timer_callback callback)
{
	if (callback == nullptr)
	{
		return;
	}

	if (num_timer_callbacks == MAX_TIMER_CBS)
	{
		return;
	}

	timer_callbacks[num_timer_callbacks++] = callback;
}

void timer_unregister_callback(const timer_callback callback)
{
	if (callback == nullptr)
	{
		return;
	}

	for (int i = 0; i < num_timer_callbacks; i++)
	{
		if (timer_callbacks[i] == callback)
		{
			timer_callbacks[i] = timer_callbacks[num_timer_callbacks - 1];
			num_timer_callbacks--;
			break;
		}
	}
}

void handle_timer_1()
{
	for (int i = 0; i < num_timer_callbacks; i++)
	{
		u64 time = timer_get_ticks();
		timer_callbacks[i](time);
	}
}

void handle_timer_3()
{
}

#ifdef __cplusplus
}
#endif
