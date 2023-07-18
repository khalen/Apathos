#pragma once

#include "base_defs.h"

#ifdef __cplusplus
extern "C"
{
#endif
void *memzero(void *dest, u64 n);
void *memset(void *dest, u64 c, u64 n);
void *memcpy(void *dest, const void* src, u64 n);
void *memmove(void *dest, const void* src, u64 n);
i64	memcmp(const void* a, const void* b, u64 n);
u64 strlen(const char* str);
char* strchr(char* str, u64 c);

void init_mmu_verbose();
#ifdef __cplusplus
}
#endif
