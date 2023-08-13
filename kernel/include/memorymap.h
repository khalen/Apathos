#ifndef MEMORYMAP_H
#define MEMORYMAP_H

#define SYS_GIGS				8				// The mem size of the Pi in GB
#ifndef MEGABYTE
	#define MEGABYTE			0x100000
#endif
#ifndef GIGABYTE
	#define GIGABYTE			0x40000000UL
#endif

#define CORES					4

#define MEM_SIZE				(512 * MEGABYTE)
#define GPU_MEM_SIZE			(64 * MEGABYTE)
#define ARM_MEM_SIZE			(MEM_SIZE - GPU_MEM_SIZE)

#define PAGE_SIZE				0x10000

#define EXCEPTION_STACK_SIZE	0x8000
#define PAGE_RESERVE			(16 * MEGABYTE)

#define KERNEL_MAX_SIZE			(2 * MEGABYTE)
#define KERNEL_STACK_SIZE		0x20000
#define MEM_KERNEL_START		0x80000
#define MEM_KERNEL_END			(MEM_KERNEL_START + KERNEL_MAX_SIZE)
#define MEM_KERNEL_STACK		(MEM_KERNEL_END + KERNEL_STACK_SIZE)
#define MEM_EXCEPTION_STACK		(MEM_KERNEL_STACK + KERNEL_STACK_SIZE * (CORES-1) + EXCEPTION_STACK_SIZE)
#define MEM_EXCEPTION_STACK_END	(MEM_EXCEPTION_STACK + EXCEPTION_STACK_SIZE * (CORES-1))

// Coherent memory region (4 MB) for DMA
#define MEM_COHERENT_REGION		((MEM_EXCEPTION_STACK_END + 2*MEGABYTE) & ~(MEGABYTE-1))

#define MEM_HEAP_START			(MEM_COHERENT_REGION + 4*MEGABYTE)

// High memory region (not safe for DMA)
#define MEM_HIGHMEM_START		GIGABYTE
#define MEM_HIGHMEM_END			(SYS_GIGS * GIGABYTE - 1)

#endif