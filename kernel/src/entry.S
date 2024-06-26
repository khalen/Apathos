// -*- tab-width: 8; -*-

#include "entry.h"

.macro kernel_entry
	sub	sp, sp, #STACK_FRAME_SIZE
	stp	x0,  x1,  [sp, #16 *  0]
	stp	x2,  x3,  [sp, #16 *  1]
	stp	x4,  x5,  [sp, #16 *  2]
	stp	x6,  x7,  [sp, #16 *  3]
	stp	x8,  x9,  [sp, #16 *  4]
	stp	x10, x11, [sp, #16 *  5]
	stp	x12, x13, [sp, #16 *  6]
	stp	x14, x15, [sp, #16 *  7]
	stp	x16, x17, [sp, #16 *  8]
	stp	x18, x19, [sp, #16 *  9]
	stp	x20, x21, [sp, #16 * 10]
	stp	x22, x23, [sp, #16 * 11]
	stp	x24, x25, [sp, #16 * 12]
	stp	x26, x27, [sp, #16 * 13]
	stp	x28, x29, [sp, #16 * 14]
	str	x30,      [sp, #16 * 15]
.endm

.macro kernel_exit reboot = 0
.if	\reboot == 1
	ldr	x0, =fith_abort
	msr	elr_el1, x0
.endif

	ldp	x0,  x1,  [sp, #16 *  0]
	ldp	x2,  x3,  [sp, #16 *  1]
	ldp	x4,  x5,  [sp, #16 *  2]
	ldp	x6,  x7,  [sp, #16 *  3]
	ldp	x8,  x9,  [sp, #16 *  4]
	ldp	x10, x11, [sp, #16 *  5]
	ldp	x12, x13, [sp, #16 *  6]
	ldp	x14, x15, [sp, #16 *  7]
	ldp	x16, x17, [sp, #16 *  8]
	ldp	x18, x19, [sp, #16 *  9]
	ldp	x20, x21, [sp, #16 * 10]
	ldp	x22, x23, [sp, #16 * 11]
	ldp	x24, x25, [sp, #16 * 12]
	ldp	x26, x27, [sp, #16 * 13]
	ldp	x28, x29, [sp, #16 * 14]
	ldr	x30,      [sp, #16 * 15]
	add	sp, sp, #STACK_FRAME_SIZE

	eret
.endm

.macro ventry label
.align 7
	b	\label
.endm

.macro handle_invalid_entry type
	mov	x22, x0
	kernel_entry
	mov	x0, #\type
	mrs	x1, esr_el1
	mrs	x2, elr_el1
	mov	x3, x21
	mov	x4, x19
	mov	x5, x20
	mov	x6, x22
	bl	show_invalid_entry_message
	kernel_exit 1
	b	err_hang
.endm

.align 11
.globl exception_vectors

exception_vectors:
	ventry	sync_invalid_el1t
	ventry	irq_invalid_el1t
	ventry	fiq_invalid_el1t
	ventry	error_invalid_el1t

	ventry	sync_invalid_el1h
	ventry	handle_el1_irq
	ventry	fiq_invalid_el1h
	ventry	error_invalid_el1h

	ventry	sync_invalid_el0_64
	ventry	irq_invalid_el0_64
	ventry	fiq_invalid_el0_64
	ventry	error_invalid_el0_64

	ventry	sync_invalid_el0_32
	ventry	irq_invalid_el0_32
	ventry	fiq_invalid_el0_32
	ventry	error_invalid_el0_32

sync_invalid_el1t:
	handle_invalid_entry	SYNC_INVALID_EL1T
irq_invalid_el1t:
	handle_invalid_entry	IRQ_INVALID_EL1T
fiq_invalid_el1t:
	handle_invalid_entry	FIQ_INVALID_EL1T
error_invalid_el1t:
	handle_invalid_entry	ERROR_INVALID_EL1T

sync_invalid_el1h:
	handle_invalid_entry	SYNC_INVALID_EL1H
// irq_invalid_el1h:
//	handle_invalid_entry	IRQ_INVALID_EL1H
fiq_invalid_el1h:
	handle_invalid_entry	FIQ_INVALID_EL1H
error_invalid_el1h:
	handle_invalid_entry	ERROR_INVALID_EL1H

sync_invalid_el0_64:
	handle_invalid_entry	SYNC_INVALID_EL0_64
irq_invalid_el0_64:
	handle_invalid_entry	IRQ_INVALID_EL0_64
fiq_invalid_el0_64:
	handle_invalid_entry	FIQ_INVALID_EL0_64
error_invalid_el0_64:
	handle_invalid_entry	ERROR_INVALID_EL0_64

sync_invalid_el0_32:
	handle_invalid_entry	SYNC_INVALID_EL0_32
irq_invalid_el0_32:
	handle_invalid_entry	IRQ_INVALID_EL0_32
fiq_invalid_el0_32:
	handle_invalid_entry	FIQ_INVALID_EL0_32
error_invalid_el0_32:
	handle_invalid_entry	ERROR_INVALID_EL0_32

handle_el1_irq:
	kernel_entry
	bl	handle_irq
	kernel_exit 0

.globl err_hang
err_hang:
	b	err_hang
