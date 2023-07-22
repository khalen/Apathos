// -*-  tab-width 4; -*-

#include "base_defs.h"
#include "kernel.h"
#include "linenoise.h"
#include "mem.h"
#include "mini_uart.h"
#include "peripherals/base.h"
#include "printf.h"
#include "timer.h"
#include "utils.h"

CKernel gKernel;

CKernel::CKernel()
	: CpuThrottle(TCPUSpeed::CPUSpeedMaximum), Timer(&Interrupt),
	  Logger(4, &Timer)
{
}

CKernel::~CKernel()
{}

bool CKernel::Initialize()
{
	bool ok = true;

	ok = Serial.Initialize(921600);
	if (ok)
	{
		CDevice *target = DeviceNameService.GetDevice( Options.GetLogDevice(), false );
		if (target == nullptr)
		{
			target = &Serial;
		}

		ok = Logger.Initialize(target);
	}
	ok = ok && Interrupt.Initialize();
	ok = ok && Timer.Initialize();

	return ok;
}

extern "C"
{
void fith_boot(u64);

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

u64 kernel_readline(char *destBuffer, u64 maxLen, u64 prompt)
{
	const char *lineOut = linenoise(prompt ? "> " : "");
	u64			len		= strlen(lineOut);
	memcpy(destBuffer, lineOut, len);
	destBuffer[len] = 10;
	return len + 1;
}

void _putchar(char c)
{
	uart_putc(c);
}

void magicCallback(void)
{
	printf("**** Rebooting.. Like magic!\n");
	rebootSystem();
}

///// TOP LEVEL ENTRY POINT /////

int main(void)
{
	const char *excLevelNames[] = {"User", "Kernel", "Hypervisor", "Firmware"};

	bool success = gKernel.Initialize();

	if (!success)
	{
		CLogger::Get()->Write("Kernel", LogPanic, "Kernel failed to initialize.");

		while (1)
		{
			asm volatile ("nop");
		}
	}

	gKernel.Serial.RegisterMagicReceivedHandler("\x12", magicCallback);

	uart_init();
	u64 excLevel = get_el();
	printf("\nHello from Apathos. Running at exception level: %d (%s)\n", excLevel, excLevelNames[excLevel]);
	printf("Initializing kernel...\n");

	printf("Booting FITH v.-3.1415927\n");
	gKernel.Timer.SimpleMsDelay(10000);
	printf("Booting FITH v.-3.1415927\n");

	u8	*fithMem = new u8[1024 * 1024 * 1024];

	int loopCnt = 0;
	while (loopCnt < 10)
	{
		fith_boot((u64)fithMem);
		printf("Fell out of Fith execution loop. Restarting...\n");
		loopCnt++;
	}
	printf("Fell out of Fith execution loop too many times. Rebooting...\n");
	rebootSystem();
}
}
