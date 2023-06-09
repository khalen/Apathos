#pragma once

#include "base_defs.h"

// VideoCore IRQs.

// 6.2.4 of the datasheet
#define	SYS_TIMER_0_IRQ  (1u <<  0)
#define SYS_TIMER_1_IRQ  (1u <<  1)
#define	SYS_TIMER_2_IRQ  (1u <<  2)
#define SYS_TIMER_3_IRQ  (1u <<  3)
#define	AUX_IRQ          (1u << 29)

typedef struct PACKED
{
	reg32 data[3];
	reg32 _reserved;
} IrqData;
static_assert(sizeof(IrqData) == 16, "IrqData struct has unexpected size");

// This will differ on Pi3, if we ever decide to port to it.
typedef struct PACKED
{
	IrqData Irq0Pending;
	IrqData Irq0Enable;
	IrqData Irq0Disable;
} IrqRegs;

#define IRQ_REGS ((IrqRegs *)(PERIPHERAL_BASE + 0xB200))
