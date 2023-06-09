// -*-  tab-width 4; -*-

#include "base_defs.h"
#include "utils.h"
#include "printf.h"
#include "mini_uart.h"
#include "irq.h"
#include "timer.h"
#include "mem.h"

extern "C"
{
void printfPutC( void*, char c )
{
	uart_putc(c);
}

void rebootSystem()
{
	// This is taken from code that worked on the rpi 2. Hopefully it still works here.
	u64 PM_RSTC = (PERIPHERAL_BASE + 0x10001c);
	u64 PM_WDOG = (PERIPHERAL_BASE + 0x100024);
	const u32 PM_PASSWORD = 0x5a000000;
	const u32 PM_RSTC_WRCFG_FULL_RESET = 0x20;

	uart_puts("***** Rebooting the system *****\n");

	put32(PM_WDOG, PM_PASSWORD | 1000);
	put32(PM_RSTC, PM_PASSWORD | PM_RSTC_WRCFG_FULL_RESET);
	delay(0xFFFFFFFFFFFF);
}

typedef struct PACKED
{
	u16	dummy0;
	u64	testValue;
} AccessTest;

void getKernel()
{
	// Initiate xfer
	for (int i = 0; i < 3; i++)
	{
		uart_putb('\x03');
	}

	i32	recvFileSize = 0;
	for (int i = 0; i < 4; i++)
	{
		recvFileSize += ((i32)uart_getb()) << (8 * i);
	}
	uart_putb('O'); uart_putb('K');

	u8* output = (u8 *)(1ul * GB);
	uart_read(output, recvFileSize);
	printf("*** Read %ld bytes.\n");
}

int main()
{
	const char* excLevelNames[] = { "User", "Kernel", "Hypervisor", "Firmware" };

	// set up serial console
	uart_init();
	init_printf(NULL, printfPutC);

	u32 excLevel = get_el();
	printf("\n\nHello from Apathos. Running at exception level: %d (%s)\n\n", excLevel, excLevelNames[excLevel]);

	// Set up the exception handler vectors
	irq_init_vectors();

	// Configure the irq controller to enable the specific IRQs we want
	enable_interrupt_controller();

	// Turn on all IRQs
	irq_enable();
	timer_init();

	// Test that the MMU is configured properly. RAM should run from 0x00 -> 8g with the device section representing a "hole" of 64mb starting at PERIPHERAL_BASE.
	const u64 testValue = 0xDEADBEEFBADF00D0ul;

	printf("Unaligned check write:\n");
	// Test unaligned access. This will throw a sync error execption if the MMU isn't enabled.
	volatile AccessTest *testerPtr = (AccessTest *)(3ul * GB);
	testerPtr->testValue = testValue;

	timer_sleep_ms(3000);

	u64 checkVal = testerPtr->testValue;
	printf("  Read: %s!\n\n", checkVal == testValue ? "Success" : "Fail");

	// getKernel();

	// echo everything back
	while(1)
	#if 0
	{
		char c = uart_getc();
		if (c == '\\')
			rebootSystem();
		uart_putc(c);
	}
	#else
		;
	#endif

	return 0;
}
}
