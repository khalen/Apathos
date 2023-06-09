#pragma once

#include <stdarg.h>

extern "C"
{
typedef void (*PutcFuncType)(void *, char);

void init_printf(void* putp, PutcFuncType putc_proc);

void tfp_printf(const char *fmt, ...);
void tfp_sprintf(char *s, const char *fmt, ...);

void tfp_format(void* putp, PutcFuncType putc_proc, const char *fmt, va_list va);
}

#define printf tfp_printf
#define sprintf tfp_sprintf
