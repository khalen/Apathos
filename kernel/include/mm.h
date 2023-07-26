#pragma once

#include "base_Defs.h"
#define PAGE_SHIFT     12
#define TABLE_SHIFT    9
#define SECTION_SHIFT  (PAGE_SHIFT + TABLE_SHIFT)
#define PG_SIZE      (1 << PAGE_SHIFT)
#define SECTION_SIZE   (1 << SECTION_SHIFT)

#define LOW_MEMORY     (2 * SECTION_SIZE)

#ifdef __cplusplus
extern "C"
{
#endif

u64 getCoherentPage(u64 slot);

#ifdef __cplusplus
}
#endif
