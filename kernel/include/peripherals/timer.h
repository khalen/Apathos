#pragma once

#include "base_defs.h"
#include "peripherals/base.h"

// 1mhz clock frequency
#define CLOCK_HZ	1000000

// 10.2 of the datasheet
typedef struct PACKED
{
	reg32	CtrlStatus;
	reg32	CounterLow;
	reg32	CounterHigh;
	reg32	Compare[4];
} TimerRegs;

static_assert(sizeof(TimerRegs) == 0x1c, "TimerRegs structure has unexpected size");

#define TIMER_REGS		((TimerRegs *)(PERIPHERAL_BASE + 0x3000))
