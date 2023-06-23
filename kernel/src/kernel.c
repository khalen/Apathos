// -*-  tab-width 4; -*-

#include "base_defs.h"
#include "irq.h"
#include "mem.h"
#include "mini_uart.h"
#include "printf.h"
#include "timer.h"
#include "utils.h"
#include "linenoise.h"

extern "C"
{
void fith_boot();

void _putchar(char c)
{
	uart_putc(c);
}

void rebootSystem()
{
	// This is taken from code that worked on the rpi 2. Hopefully it still works here.
	u64		  PM_RSTC				   = (PERIPHERAL_BASE + 0x10001c);
	u64		  PM_WDOG				   = (PERIPHERAL_BASE + 0x100024);
	const u32 PM_PASSWORD			   = 0x5a000000;
	const u32 PM_RSTC_WRCFG_FULL_RESET = 0x20;

	uart_puts("***** Rebooting the system *****\n");

	put32(PM_WDOG, PM_PASSWORD | 1000);
	put32(PM_RSTC, PM_PASSWORD | PM_RSTC_WRCFG_FULL_RESET);
	delay(0xFFFFFFFFFFFF);
}

void getKernel()
{
	// Initiate xfer
	for (int i = 0; i < 3; i++)
	{
		uart_putb('\x03');
	}

	i32 recvFileSize = 0;
	for (int i = 0; i < 4; i++)
	{
		recvFileSize += ((i32)uart_getb()) << (8 * i);
	}
	uart_putb('O');
	uart_putb('K');

	u8 *output = (u8 *)(1ul * GB);
	uart_read(output, recvFileSize);
	printf("*** Read %ld bytes.\n");
}

u64	kernel_readline(char *destBuffer, u64 maxLen)
{
	const char* lineOut = linenoise("> ");
	u64 len = strlen(lineOut);
	memcpy(destBuffer, lineOut, len);
	return len;
}

///// TOP LEVEL ENTRY POINT /////
int kernel_entry()
{
	const char *excLevelNames[] = {"User", "Kernel", "Hypervisor", "Firmware"};

	// set up serial console
	uart_init();

	u32 excLevel = get_el();
	printf("\n\nHello from Apathos. Running at exception level: %d (%s)\n\n", excLevel, excLevelNames[excLevel]);

	// Set up the exception handler vectors
	irq_init_vectors();

	// Configure the irq controller to enable the specific IRQs we want
	enable_interrupt_controller();

	// Turn on all IRQs
	irq_enable();
	timer_init();

	printf("\n\nBooting FITH v.-3.1415927\n");

	fith_boot();

	return 0;
}
}
