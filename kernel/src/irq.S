// -*- tab-width: 8; -*-

#include "entry.h"

// D13.2.137 in Aarch64-A reference
.globl irq_init_vectors
irq_init_vectors:
	adr	x0, exception_vectors
	msr	vbar_el1, x0
	ret

// C5.2.2
.globl irq_enable
irq_enable:
	msr	daifclr, #2
	ret

.globl irq_disable
irq_disable:
	msr	daifset, #2
	ret
