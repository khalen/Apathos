// -*- tab-width: 8; -*-

.section ".text.boot"

.global _start

_start:
        // Save away args that will be trashed by any C calls that are part of the boot protocol
        mov     x20, x0
        mov     x21, x1
        mov     x22, x2
        mov     x23, x3

        // Read cpu id, stop all but core 0
        mrs     x1, mpidr_el1
        and     x1, x1, #3
        cbz     x1, core_zero

        // cpu id > 0, park
spin:
        wfe
        b       spin

        // cpu id == 0
core_zero:
        // Put C stack somewhere out of the way for now
        ldr     x2, =0x2000000
        mov     sp, x2

        // relocate our code from load address to link address
        ldr     x1, =LOAD_ADDR
        mov     x0, x1
        ldr     x2, =_start
        ldr     w3, =__loader_size
1:      ldr     x4, [x1], #8
        str     x4, [x2], #8
        sub     w3, w3, #1
        cbnz    w3, 1b

        // Jump to relocated C code.
        bl      receiver - 2048

        // restore registers and jump to new kernel's entry point
        ldr     x30, =LOAD_ADDR
        mov     x0, x20
        mov     x1, x21
        mov     x2, x22
        mov     x3, x23
        ret
