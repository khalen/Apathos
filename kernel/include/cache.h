#ifndef CACHE_H_
#define CACHE_H_

#include "base_defs.h"

#define SETWAY_LEVEL_SHIFT              1

#define L1_DATA_CACHE_SETS              256
#define L1_DATA_CACHE_WAYS              2
#define L1_SETWAY_WAY_SHIFT             31      // 32-Log2(L1_DATA_CACHE_WAYS)
#define L1_DATA_CACHE_LINE_LENGTH       64
#define L1_SETWAY_SET_SHIFT             6       // Log2(L1_DATA_CACHE_LINE_LENGTH)

#define L2_CACHE_SETS                   1024
#define L2_CACHE_WAYS                   16
#define L2_SETWAY_WAY_SHIFT             28      // 32-Log2(L2_CACHE_WAYS)
#define L2_CACHE_LINE_LENGTH            64
#define L2_SETWAY_SET_SHIFT             6       // Log2(L2_CACHE_LINE_LENGTH)

#if __cplusplus
extern "C"
{
#endif

void cleanInvalidateDCacheRange( u64 addr, u64 len );
void invalidateICache();
void dataSyncBarrier();

#if __cplusplus
}
#endif

#endif // CACHE_H_
