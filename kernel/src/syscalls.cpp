#include "base_defs.h"
#include "mini_uart.h"
#include "syscalls.h"
#include "printf.h"
#include <fatfs/ff.h>

u64 syscall_table[SYSCALL_MAX];

#define SCALL(idx, name) \
	syscall_table[idx] = (u64)((uintptr_t)name)

u64 syscall_6test(u64 a, u64 b, u64 c, u64 d, u64 e, u64 f)
{
	printf( "6 args: 0x%llx, 0x%llx, 0x%llx, 0x%llx, 0x%llx, 0x%llx\n", a, b, c, d, e, f );
	return 6;
}

u64 syscall_5test(u64 a, u64 b, u64 c, u64 d, u64 e)
{
	printf( "5 args: 0x%llx, 0x%llx, 0x%llx, 0x%llx, 0x%llx\n", a, b, c, d, e );
	return 5;
}

u64 syscall_4test(u64 a, u64 b, u64 c, u64 d)
{
	printf( "4 args: 0x%llx, 0x%llx, 0x%llx, 0x%llx\n", a, b, c, d );
	return 4;
}

u64 syscall_3test(u64 a, u64 b, u64 c)
{
	printf( "3 args: 0x%llx, 0x%llx, 0x%llx\n", a, b, c );
	return 3;
}

u64 syscall_2test(u64 a, u64 b)
{
	printf( "2 args: 0x%llx, 0x%llx\n", a, b);
	return 2;
}

u64 syscall_1test(u64 a)
{
	printf( "1 args: 0x%llx\n", a);
	return 1;
}

u64 syscall_0test()
{
	printf( "0 args\n");
	return 0;
}

void syscall_unknown()
{
	uart_puts("Unknown syscall!\n");
}

void syscalls_init()
{
	for (int i = 0; i < SYSCALL_MAX; i++)
	{
		SCALL(i, syscall_unknown);
	}

	SCALL(10, syscall_0test);
	SCALL(11, syscall_1test);
	SCALL(12, syscall_2test);
	SCALL(13, syscall_3test);
	SCALL(14, syscall_4test);
	SCALL(15, syscall_5test);
	SCALL(16, syscall_6test);
}
