#pragma once

typedef char           i8;
typedef unsigned char  u8;

typedef short          i16;
typedef unsigned short u16;

typedef int            i32;
typedef unsigned int   u32;

typedef long           i64;
typedef unsigned long  u64;
typedef u64            addr_t;

typedef volatile u32   reg32;
typedef volatile u64   reg64;

#define KB    1024
#define MB    (1024 * KB)
#define GB    (1024 * MB)

#define NULL  ((void *)0)

#define PACKED __attribute__((packed))
