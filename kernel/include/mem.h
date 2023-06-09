#pragma once

#include "base_defs.h"

extern "C"
{
void *memzero(void *dest, u64 n);
void *memcpy(void *dest, const void* src, u64 n);
void init_mmu_verbose();
}
