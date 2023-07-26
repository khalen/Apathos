#include "cache.h"
#include "circle/synchronize.h"

#if __cplusplus
extern "C"
{
#endif

void invalidateICache()
{
	asm volatile ("ic iallu" ::: "memory");
}

void dataSyncBarrier()
{
	asm volatile("dsb sy" ::: "memory");
}

void cleanInvalidateDCacheRange(u64 addr, u64 len)
{
	while (1)
	{
		asm volatile ("dc cvac, %0" : : "r" (addr) : "memory");

		if (len <= DATA_CACHE_LINE_LENGTH_MIN)
		{
			break;
		}

		addr += DATA_CACHE_LINE_LENGTH_MIN;
		len  -= DATA_CACHE_LINE_LENGTH_MIN;
	}

	dataSyncBarrier();
}

#if __cplusplus
}
#endif
