#include "mini_uart.h"
#include "base_defs.h"
#include "peripherals/aux.h"
#include "peripherals/gpio.h"

extern "C"
{

#define IO_QUEUE_SIZE 128
#define IO_QUEUE_MASK ~(IO_QUEUE_SIZE - 1)

struct IOQueue
{
    u8	buffer[IO_QUEUE_SIZE];
    u64 headIdx;
    u64 tailIdx;
};

bool io_queue_empty(IOQueue *queue)
{
    return queue->headIdx == queue->tailIdx;
}

void io_enqueue(IOQueue *queue, u8 value)
{
    u64 nextTail = (queue->tailIdx + 1) & IO_QUEUE_MASK;
    if (nextTail == queue->headIdx)
        return;
    queue->buffer[nextTail] = value;
    queue->tailIdx			= nextTail;
}

u8 io_dequeue(IOQueue *queue)
{
    return 0;
}

void handle_uart_irq()
{
}

void uart_init()
{
    AUX_REGS->Enables	= 1;
    AUX_REGS->MuIerReg	= 0xD; // Enable recv interrupt
    AUX_REGS->MuCntlReg = 0;
    AUX_REGS->MuLcrReg	= 3;
    AUX_REGS->MuIirReg	= 0xC6;
    AUX_REGS->MuBaudReg = AUX_MU_BAUD(921600);

    gpio_useAsAlt5(14);
    gpio_useAsAlt5(15);

    AUX_REGS->MuCntlReg = 3;
}

// Send a byte
void uart_putb(u8 c)
{
    while (!uart_isWriteByteReady())
        asm volatile("nop");

    AUX_REGS->MuIoReg = c;
}

u8 uart_getb()
{
    while (!uart_isReadByteReady())
        asm volatile("nop");

    u32 val = AUX_REGS->MuIoReg;
    return val & 0xFF;
}

char uart_getc()
{
    return (char)uart_getb();
}

// Send a chr, doing nl / lf translation
void uart_putc(i8 c)
{
    if (c == '\n')
    {
        uart_putb('\r');
    }

    uart_putb(c);
}

// Display a C style (null terminated) string
void uart_puts(const char *s)
{
    if (s == NULL)
        return;

    while (*s)
    {
        uart_putc(*s++);
    }
}

void uart_putHexByte(u8 byte)
{
    static const char hexDigits[] = "0123456789ABCDEF";

    uart_putb(hexDigits[(byte >> 4) & 0xF]);
    uart_putb(hexDigits[(byte >> 0) & 0xF]);
}

void uart_putHexShort(u16 word)
{
    uart_putHexByte((word >> 8) & 0xFF);
    uart_putHexByte((word >> 0) & 0xFF);
}

void uart_putHexWord(u32 word)
{
    uart_putHexShort((word >> 16) & 0xFFFF);
    uart_putHexShort((word >> 0) & 0xFFFF);
}

void uart_putHexLong(u64 word)
{
    uart_putHexWord((word >> 32) & 0xFFFFFFFF);
    uart_putHexWord((word >> 0) & 0xFFFFFFFF);
}

void uart_write(const u8 *buf, u64 len)
{
    while (len != 0)
    {
        uart_putb(*buf++);
        len--;
    }
}

void uart_writeText(const char *buf, u64 len)
{
    while (len != 0)
    {
        uart_putc(*buf++);
        len--;
    }
}

void uart_read(u8 *buf, u64 len)
{
    for (u64 i = 0; i < len; i++)
    {
        buf[i] = uart_getb();
    }
}
}
