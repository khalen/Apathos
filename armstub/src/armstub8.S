.section .text

// Simple replacement armstub that just leaves the el at 3 after boot. Does not park cores etc.
.globl _start
_start:
	ldr	w0, kernel_entry32
	br x0

.ltorg

.org 0xF0
	// This exact value must be at 0xF0 or the boot loader assumes our stub is invalid
.globl stub_magic
stub_magic:
	.word 0x5afe570b

.org 0xF4
.globl stub_version
stub_version:
	.word 0

.org 0xFC
.globl kernel_entry32
kernel_entry32:
	.word 0x0
