#include "mini_uart.h"
#include "base_defs.h"
#include "mem.h"
#include "printf.h"
#include <circle/devicenameservice.h>
#include <circle/serial.h>

#ifdef __cplusplus
extern "C"
{
#endif

static CDevice  *pSerial = nullptr;

void uart_putb(u8 b)
{
    pSerial->Write(&b, 1);
}
u8 uart_getb()
{
    u8 b = 0;
    while (pSerial->Read(&b, 1) == 0)
        ;
    return b;
}

char uart_getc()
{
    u8 b = 0;
    while (pSerial->Read(&b, 1) == 0)
        ;
    return (char)b;
}

void uart_putc(const char c)
{
    if (c == '\n')
        uart_putb(10);
    uart_putb(c);
}
void uart_write(const void *buffer, u64 len)
{
    const u8 *buf = (const u8 *)buffer;
    while (len != 0)
    {
        uart_putb(*buf++);
        len--;
    }
}
u64 uart_read(void *buffer, u64 len)
{
    u8 *buf = (u8 *)buffer;
    u64 i = 0;
    for (i = 0; i < len; i++)
    {
        buf[i] = uart_getb();
    }

    return i;
}

void uart_puts(const char *str)
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

void uart_init()
{
    CDeviceNameService  *nameService = CDeviceNameService::Get();
    pSerial = nameService->GetDevice("ttyS1", false);
}

// Send a byte
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

void uart_writeText(const char *buf, u64 len)
{
    while (len != 0)
    {
        uart_putc(*buf++);
        len--;
    }
}

#ifdef __cplusplus
}
#endif
