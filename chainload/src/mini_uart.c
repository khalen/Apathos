#include "mini_uart.h"
#include "base_defs.h"
#include "peripherals/aux.h"
#include "peripherals/gpio.h"

extern "C"
{
void uart_init()
{
    AUX_REGS->Enables	= 1;
    AUX_REGS->MuCntlReg = 0;
    AUX_REGS->MuIerReg	= 0; // Enable recv interrupt
    AUX_REGS->MuLcrReg	= 3;
    AUX_REGS->MuMcrReg	= 0;
    AUX_REGS->MuBaudReg = AUX_MU_BAUD(921600);

    AUX_REGS->MuCntlReg = 3;

    gpio_useAsAlt5(14);
    gpio_useAsAlt5(15);

    AUX_REGS->MuCntlReg = 3;
}

// Send a byte
void uart_putb(u8 c)
{
    while (!uart_isWriteByteReady())
        asm volatile("nop"); // Wait until we can write

    AUX_REGS->MuIoReg = c;
}

u8 uart_getb()
{
    while (!uart_isReadByteReady())
        asm volatile("nop"); // Wait until we can read

    u32 val = AUX_REGS->MuIoReg;
    return val & 0xFF;
}

void uart_putc(char c)
{
    while (!uart_isWriteByteReady())
        asm volatile("nop");

    AUX_REGS->MuIoReg = c;
}

// Display a C style (null terminated) string
void uart_puts(const char *s)
{
    if (s == NULL)
        return;

    while (*s)
    {
        uart_putb(*s++);
    }
}
}
