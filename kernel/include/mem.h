#pragma once

#include "base_defs.h"

extern "C"
{
void *memzero(void *dest, u64 n);
void *memcpy(void *dest, const void* src, u64 n);
void *memmove(void *dest, const void* src, u64 n);
u64 strlen(const char* str);
void init_mmu_verbose();
}
