SECTIONS
{
	. = 0x80000;

	.text : {
	      KEEP( *(.text.boot) ) *(.text .text.* .gnu.linkonce.t*)
	}

	.rodata : {
		*(.rodata .rodata.* .gnu.linkonce.r*)

	}

	PROVIDE(_data = .);
	.data : {
	      *(.data .data.* .gnu.linkonce.d*)
	}

	.bss (NOLOAD) : {
	     . = ALIGN(16);
	     __bss_start = .;
	     *(.bss .bss.*)
	     *(COMMON)
	     __bss_end = .;
	}

	. = ALIGN(0x00001000);
	id_pgd = .;
	.data.id_pgd : { . += (11 * 1 << 12); } # 11 pages: 1 PUD, 1 PUD, 8 PDD for main memory, 1 PDD for device memory

	_end = .;

	/DISCARD/ : {
		  *(.comment) *(.gnu*) *(.note*) *(.eh_frame*)
	}
}

__bss_size = (__bss_end - __bss_start) >> 3;
