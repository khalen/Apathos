// -*- tab-width: 8; -*-

#include "mm.h"
#include "mmu.h"
#include "sysregs.h"

.section ".text.boot"

.global _start		// Execution starts here (duh)

_start:
	mrs	x0, mpidr_el1	// Check processor ID
	and	x0, x0, #0xFF
	cbz	x0, master_core
	b	proc_hang

master_core:
	// Disable MMU for el1
	ldr	x0, =SCTLR_VALUE_MMU_DISABLED
	msr	sctlr_el1, x0

	// Ensure el0 and el1 run in 64 bit mode - not sure why this is called the "RW" bit
	ldr	x0, =HCR_VALUE
	msr	hcr_el2, x0

	// Ensure el2 runs in 64 bit mode and els lower than 3 are in non secure state, which means they can't access Secure memory.
	ldr	x0, =SCR_VALUE
	msr	scr_el3, x0

	// Set interrupt mask and configure switch to el1
	ldr	x0, =SPSR_VALUE
	msr	spsr_el3, x0

	// Init mmu to have an identity mapping
	ldr	x0, =CPACR_EL1_VALUE
	msr	cpacr_el1, x0

	ldr	x0, =TCR_EL1_VALUE
	msr	tcr_el1, x0

	ldr	x0, =MAIR_EL1_VALUE
	msr	mair_el1, x0

	// Switch to el1 starting @el1_entry
	adr	x0, el1_entry
	msr	elr_el3, x0

	eret

el1_entry:
	// Set up stack start in el3 to start at LOW_MEMORY (4mb)
	ldr	x0, =LOW_MEMORY
	mov	sp, x0

	// Zero out BSS
	ldr	x0, =__bss_start
	ldr	w1, =__bss_size
3:	cbz	w1, 4f			// Leave loop ifz
	str	xzr, [x0], #8		// Store zero in x1, inc x1 by 8
	sub	w1, w1, #1
	cbnz	w1, 3b		 	// Loop if non zero

	// Set up page tables etc. for linear mapping
	bl	init_mmu

	adrp	x0, id_pgd
	msr	ttbr0_el1, x0

	// Actually enable the mmu!
	mrs	x0, sctlr_el1
	mov	x1, #1
	orr	x0, x0, x1
	msr	sctlr_el1, x0

4:	bl	kernel_entry
	b	proc_hang		 // If main returns, jump to the inf loop as if not the main core

	// Wait for event forever
proc_hang:
	wfe
	b proc_hang

.global id_pgd_addr
id_pgd_addr:
	adrp	x0, id_pgd
	ret
