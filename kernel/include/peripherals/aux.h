#pragma once

#include "base_defs.h"
#include "peripherals/base.h"
#include "peripherals/gpio.h"

extern "C" {

typedef struct PACKED
{
	reg32 Irq;
	reg32 Enables;
	reg32 _reserved0[14];
	reg32 MuIoReg;
	reg32 MuIerReg;
	reg32 MuIirReg;
	reg32 MuLcrReg;
	reg32 MuMcrReg;
	reg32 MuLsrReg;
	reg32 MuMsrReg;
	reg32 MuScratch;
	reg32 MuCntlReg;
	reg32 MuStatReg;
	reg32 MuBaudReg;
} AuxRegs;
static_assert(sizeof(AuxRegs) == 0x6C, "AuxMMIO has invalid size");

#define AUX_REGS   ((AuxRegs *)(PERIPHERAL_BASE + 0x215000))

#define AUX_UART_CLOCK   500000000
#define UART_MAX_QUEUE   16 * KB

#define AUX_MU_BAUD(val)  ((AUX_UART_CLOCK / (val * 8)) - 1)
}
