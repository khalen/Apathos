#include "base_defs.h"
#include "mini_uart.h"

#define MIN_KERNEL_SIZE		32
#define MAX_KERNEL_SIZE		128 * 1024 * 1024	/* 128 mb should be plenty? */

extern "C"
{

// Main entry point - passed load address, returns new kernel addr
void receiver(char *loadaddr)
{
	u32 size = 0;
	char *kernel = loadaddr;

	uart_init();
	uart_puts("\r\n\r\nBooting chainloader, USB...\r\n");

	do
	{
		uart_putb(3);
		uart_putb(3);
		uart_putb(3);

		size = uart_getb();
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

	asm volatile("mov x0, x20");
	asm volatile("mov x1, x21");
	asm volatile("mov x2, x22");
	asm volatile("mov x3, x23");

	((void (*)())(loadaddr)) ();
}

}
