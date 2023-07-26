#include "base_defs.h"
#include "circle/interrupt.h"
#include <circle/startup.h>
#include <circle/serial.h>
#include <circle/devicenameservice.h>
#include <circle/chainboot.h>
#include <circle/logger.h>
#include <circle/koptions.h>
#include <circle/exceptionhandler.h>
#include <circle/timer.h>
#include <circle/screen.h>
#include <circle/cputhrottle.h>
#include <circle/koptions.h>

#define MIN_KERNEL_SIZE		32
#define MAX_KERNEL_SIZE		2 * 1024 * 1024	/* 2 mb should be plenty? */

#define TIMEOUT				3

CKernelOptions		sOptions;
CExceptionHandler	sExceptionHandler;
CCPUThrottle		sCpuThrottle(TCPUSpeed::CPUSpeedMaximum);
CDeviceNameService	sNameService;
CInterruptSystem	sInterrupts;
CSerialDevice		sSerial;
CLogger				sLogger(4, nullptr);
CTimer				sTimer(&sInterrupts);

extern "C"
{
	void uart_putb(u8 b)
	{
		while (sSerial.Write(&b, 1) != 1)
			;
	}
	u8 uart_getb_notimeout()
	{
		u8 b = 0;
		while (sSerial.Read(&b, 1) == 0)
			;
		return b;
	}
	u32 uart_getb()
	{
		u32	timeout = sTimer.GetClockTicks() + TIMEOUT * 1000 * 1000;

		u8 b = 0;
		while (sSerial.Read(&b, 1) == 0)
		{
			if (sTimer.GetClockTicks() > timeout)
			{
				return 0xFFFFFFFF;
			}
		}
		return b;
	}
	void uart_puts( const char* str )
	{
		if (!str)
			return;
		u8 c;
		while (*str)
		{
			c = *str;
			uart_putb(c);
			str++;
		}
	}
}

// Main entry point - passed load address, returns new kernel addr
int main(void)
{
	u32 size = 0;
	u8* kbuffer = new u8[MAX_KERNEL_SIZE];
	u8 *kernel = kbuffer;
	sInterrupts.Initialize();
	sSerial.Initialize(921600);
	sLogger.Initialize(&sSerial);
	sCpuThrottle.DumpStatus(true);
	sTimer.Initialize();

	uart_puts("Booting chainloader from SDCard...\r\n");

	do
	{
		uart_putb(3);
		uart_putb(3);
		uart_putb(3);

		size = uart_getb();

		if (size > 0xFF)
		{
			sTimer.SimpleMsDelay(500);
			continue;
		}

		size |= uart_getb()<<8;
		size |= uart_getb()<<16;
		size |= uart_getb()<<24;

		if(size < 32 || size >= 4*1024*1024)
		{
			uart_putb('S');
			uart_putb('E');
		}
		else
		{
			uart_putb('O');
			uart_putb('K');
			break;
		}

	} while (1);

	u32 sz = size;
	while (sz--)
	{
		*kernel++ = uart_getb();
	}

	#if 0
	while(1)
	{
		if (uart_getb_notimeout() == ' ')
			break;
	}
	#endif

	EnableChainBoot(kbuffer, size);

	return EXIT_REBOOT;
}
