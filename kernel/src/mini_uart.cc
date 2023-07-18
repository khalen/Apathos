#include "mini_uart.h"
#include "base_defs.h"
#include "mem.h"
#include "printf.h"

#include "peripherals/aux.h"
#include "peripherals/gpio.h"

#ifdef __cplusplus
extern "C"
{
#endif

#define IO_QUEUE_SIZE 128
#define IO_QUEUE_MASK (IO_QUEUE_SIZE - 1)

struct IOQueue
{
    u8	buffer[IO_QUEUE_SIZE];
    u64 headIdx;
    u64 tailIdx;
};

IOQueue inputQueue;

bool io_queue_empty(IOQueue *queue)
{
    return queue->headIdx == queue->tailIdx;
}

bool io_queue_full(IOQueue *queue)
{
    u64 nextHead = (queue->headIdx + 1) & IO_QUEUE_MASK;
    return nextHead == queue->tailIdx;
}

void io_enqueue(IOQueue *queue, u8 value)
{
    u64 nextHead = (queue->headIdx + 1) & IO_QUEUE_MASK;
    if (nextHead == queue->tailIdx)
        return;
    queue->buffer[queue->headIdx] = value;
    queue->headIdx			      = nextHead;
}

u32 io_dequeue(IOQueue *queue)
{
    if (io_queue_empty(queue))
        return 0xFFFFFFFF;
    u32 c = queue->buffer[queue->tailIdx];
    u64 nextTailIdx = (queue->tailIdx + 1) & IO_QUEUE_MASK;
    queue->tailIdx = nextTailIdx;
    return c;
}

void io_initQueue(IOQueue *queue)
{
    memzero(queue, sizeof(IOQueue));
}

u8 uart_raw_getb()
{
    while (!uart_isReadByteReady())
        asm volatile("nop");


    return AUX_REGS->MuIoReg;
}

void handle_uart_irq()
{
    char c = uart_raw_getb();
    if (c == 18)
    {
        extern void rebootSystem();
        rebootSystem();
    }
    io_enqueue(&inputQueue, c);
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
    while (io_queue_empty(&inputQueue))
        asm volatile("nop");

    return io_dequeue(&inputQueue);
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

void uart_write(const void *inBuf, u64 len)
{
    const u8 *buf = (const u8 *)inBuf;

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

u64 uart_read(void *inBuf, u64 len)
{
    u8 *buf = (u8 *)inBuf;

    for (u64 i = 0; i < len; i++)
    {
        buf[i] = uart_getb();
    }

    return len;
}

#ifdef __cplusplus
}
#endif
