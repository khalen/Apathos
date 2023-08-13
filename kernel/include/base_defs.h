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

typedef u64 size_t;
typedef i64 ssize_t;
typedef u64 uintptr_t;
typedef i64 ptrdiff_t;
typedef i64 intptr_t;

#define KB    1024
#define MB    (1024 * KB)
#define GB    (1024 * MB)

#define NULL  0

#ifndef offsetof
#define offsetof(struc, fiel) \
	__builtin_offsetof(struc, fiel)
#endif
