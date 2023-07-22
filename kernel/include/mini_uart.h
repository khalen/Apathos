#include "base_defs.h"

#ifdef __cplusplus
extern "C"
{
#endif

void uart_init();

// Write an untranslated 8 bit value
void uart_putb(u8 c);

// Write an 8 bit value, replacing '\n' with '\r'
void uart_putc(i8 c);

// Write a c style (null terminated) string, assuming text
void uart_puts(const char *s);

// Raw buffer write with no translation
void uart_write(const void *buffer, u64 len);

// Write a buffer translating '\n' to '\r'
void uart_writeText(const char* str, u64 len);

// Utilities to output hex values
void uart_putHexByte(u8 byte);
void uart_putHexShort(u16 word);
void uart_putHexWord(u32 word);
void uart_putHexLong(u64 word);

// Read a raw byte value
u8 uart_getb();

// Read a char value TODO: Should this translate \r\n or \n\r -> \n to be symmetric with output?
char uart_getc();
//
// Raw buffer write with no translation
u64 uart_read(void *buffer, u64 len);

#ifdef __cplusplus
}
#endif
