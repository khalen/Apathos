#include "printf.h"
#include "peripherals/timer.h"
#include "peripherals/irq.h"
#include "peripherals/aux.h"
#include "mini_uart.h"

extern "C"
{

static const u32 interval1 = CLOCK_HZ;
static const u32 interval3 = CLOCK_HZ / 4;

static u32 curVal1 = 0;
static u32 curVal3 = 0;

void timer_init()
{
	#if 0
	curVal1 = TIMER_REGS->CounterLow;
	curVal1 += interval1;
	TIMER_REGS->Compare[1] = curVal1;

	curVal3 = TIMER_REGS->CounterLow;
	curVal3 += interval3;
	TIMER_REGS->Compare[3] = curVal3;
	#endif
}

void handle_timer_1()
{
	curVal1 = TIMER_REGS->CounterLow + interval1;
	TIMER_REGS->Compare[1] = curVal1;
	TIMER_REGS->CtrlStatus |= SYS_TIMER_1_IRQ;

	uart_puts("Timer 1 tick\n");
}

void handle_timer_3()
{
	curVal3 = TIMER_REGS->CounterLow + interval3;
	TIMER_REGS->Compare[3] = curVal3;
	TIMER_REGS->CtrlStatus |= SYS_TIMER_3_IRQ;

	uart_puts("Timer 3 tick\n");
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

}
