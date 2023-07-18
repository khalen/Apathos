#include "irq.h"
#include "utils.h"
#include "printf.h"
#include "entry.h"
#include "peripherals/irq.h"
#include "peripherals/aux.h"
#include "mini_uart.h"
#include "timer.h"

// See entry.h
const char *entryErrorMessages[] =
{
	"SYNC_INVALID_EL1T",
	"IRQ_INVALID_EL1T",
	"FIQ_INVALID_EL1T",
	"ERROR_INVALID_EL1T",

	"SYNC_INVALID_EL1H",
	"IRQ_INVALID_EL1H",
	"FIQ_INVALID_EL1H",
	"ERROR_INVALID_EL1H",

	"SYNC_INVALID_EL0_64",
	"IRQ_INVALID_EL0_64",
	"FIQ_INVALID_EL0_64",
	"ERROR_INVALID_EL0_64",

	"SYNC_INVALID_EL0_32",
	"IRQ_INVALID_EL0_32",
	"FIQ_INVALID_EL0_32",
	"ERROR_INVALID_EL0_32",
};

extern "C"
{

// Called from the asm exception handler
void show_invalid_entry_message(u32 type, u64 esr, u64 addr, u64 fip, u64 dsp, u64 rsp, u64 x0)
{
	printf_("Exception error caught: %s - %d, ESR: 0x%lX, Addr: 0x%lX, Fip: 0x%lX, Dsp: 0x%lX, Rsp: 0x%lX, X0: 0x%lx", entryErrorMessages[type], type, esr, addr, fip, dsp, rsp, x0);
}

void enable_interrupt_controller()
{
	IRQ_REGS->Irq0Enable.data[0] = AUX_IRQ; // | SYS_TIMER_1_IRQ | SYS_TIMER_3_IRQ;
}

void disable_interrupt_controller()
{
	IRQ_REGS->Irq0Enable.data[0] = 0;
}

extern void rebootSystem();

void handle_irq()
{
	reg32 irq = 0;

	irq = IRQ_REGS->Irq0Pending.data[0];

	while(irq)
	{
		if (irq & AUX_IRQ)
		{
			irq &= ~AUX_IRQ;

			while((AUX_REGS->MuIirReg & 4) == 4)
			{
				extern void handle_uart_irq();
				handle_uart_irq();
			}
		}
		if (irq & SYS_TIMER_1_IRQ)
		{
			irq &= ~SYS_TIMER_1_IRQ;

			handle_timer_1();
		}
		if (irq & SYS_TIMER_3_IRQ)
		{
			irq &= ~SYS_TIMER_3_IRQ;

			handle_timer_3();
		}

	}
}

}
