LOAD_ADDR = 0x80000;

SECTIONS
{
	# This provides the real "magic" that lets the chainloader work. The linker calculates all addresses relative to
	# ., but the bootloader on the Pi will always load kernel8.img at the fixed LOAD_ADDR. Once our _start routine
	# copies everything to the -2048 offset though, any relative accesses or branches will be correct since
	# we're telling the linker we're 2k earlier.

	. = LOAD_ADDR - 2048;

	PROVIDE(_code = .);

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

	_end = .;

	/DISCARD/ : {
		  *(.comment) *(.gnu*) *(.note*) *(.eh_frame*)
	}
}

__loader_size = (_end - _code) >> 3;
