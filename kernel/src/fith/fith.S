// This is Fith, an arm64 Forth var48iant. It is intended to have the minimum amount of primitive words to be:
// reasonably fast, while remaining small enough to reason about. Inspired by Jonesforth, an amazing 32 bit I86
// literate Forth written in assembly. We use a different dictionary format for and a couple of tricks for
// something reasonably approaching efficiency,

// In the code below, there are a few definitions for character strings. The counted versions are byte buffers
// really, since they are 8 bit clean:
// FCS - "Full Counted String", represented by a dword pair (caddr u). Nearly always on the stack, but if a single
//    address is passed around it is the address of the length word.
// SCS - "Short Counted String", uses the Forth 1989 definition of "string" which is a single addr pointing to a
//    8 bit length N followed by N bytes of data.
// ZTS - "Zero Terminated String", this is a C string. A single address pointing to a char terminated by a 0 byte.

	.set FITH_VERSION, 42

// Reserved registers. These have been allocated from the "callee saved" registers, which makes
// interoperating with the C kernel easier. This should be less meaningful over time, as the eventual
// goal is for even the lowest level functionality to be written in Fith itself.
#define DEFAULT_INPUT_BUFFER_SIZE	1024
#define PAD_BUFFER_SIZE			1024
#define	LINE_BUFFER_SIZE		1024
#define WORD_BUFFER_SIZE		64
#define DEFAULT_DSTACK_SIZE		4096
#define DEFAULT_RSTACK_SIZE		1024
#define DEFAULT_DICT_SIZE		1024*1024
#define CONTEXT_SIZE			8		/* # dicts supported in search order */

// Important system registers
dsp	.req	x19	// Fith data stack
rsp	.req	x20	// Fith return stack
fip	.req	x21	// Fith Instruction Pointer

// Scratch registers
scx0	.req	x23
scx1	.req	x24
scx2	.req	x25
scx3	.req	x26
scx4	.req	x27
scx5	.req	x28

scw0	.req	w23
scw1	.req	w24
scw2	.req	w25
scw3	.req	w26
scw4	.req	w27
scw5	.req	w28

// Make a C ABI call. The stack must be aligned to 16b when we enter C code.
.macro	call	func_name
	stp	x29, x30, [sp, #-32]!
	bl	\func_name
	ldp	x29, x30, [sp], #32
.endm

.macro	callreg	reg
	stp	x29, x30, [sp, #-32]!
	blr	\reg
	ldp	x29, x30, [sp], #32
.endm

// Push and pop to the return stack
.macro	pushrsp	reg
	str	\reg, [rsp, #-8]!
.endm

.macro	poprsp	reg
	ldr	\reg, [rsp], #8
.endm

// Push and pop to the data stack
.macro	push	reg=x0
	str	\reg, [dsp, #-8]!
.endm

.macro	pop	reg=x0
	ldr	\reg, [dsp], #8
.endm

// These macros are written to be compatible with standard stack word notation in F. Eg.
// push3 x2, x1, x0   ( -- a b c ) again read right to left from top of stack so x2 = a, x1 = b, x0 = a
// pop3  x2, x1, x0   (a b c -- ) read right to left from top of stack, so x0 = c, x1 = b, x2 = a
// The net effect is that if you do pushn x0, x1, x2, ... then popn x0, x1, x2, ... the registers will contain
// the same values before and after.
.macro	push2	reg1=x1, reg0=x0
	str	\reg1, [dsp, #-8]!
	str	\reg0, [dsp, #-8]!
.endm

.macro	pop2	reg1=x1, reg0=x0
	ldr	\reg0, [dsp], #8
	ldr	\reg1, [dsp], #8
.endm

.macro	push3	reg2=x2, reg1=x1, reg0=x0
	str	\reg2, [dsp, #-8]!
	str	\reg1, [dsp, #-8]!
	str	\reg0, [dsp, #-8]!
.endm

.macro	pop3	reg2=x2, reg1=x1, reg0=x0
	ldr	\reg0, [dsp], #8
	ldr	\reg1, [dsp], #8
	ldr	\reg2, [dsp], #8
.endm

.macro	push4	reg3=x3, reg2=x2, reg1=x1, reg0=x0
	str	\reg3, [dsp, #-8]!
	str	\reg2, [dsp, #-8]!
	str	\reg1, [dsp, #-8]!
	str	\reg0, [dsp, #-8]!
.endm

.macro	pop4	reg3=x3, reg2=x2, reg1=x1, reg0=x0
	ldr	\reg0, [dsp], #8
	ldr	\reg1, [dsp], #8
	ldr	\reg2, [dsp], #8
	ldr	\reg3, [dsp], #8
.endm

// This is the implementation of NEXT, implemented as a macro with optional wrapper so we can indirectly
// "assemble" it into other words without having to keep it in sync in more than one place.
	#if 0
.macro	next
	ldr	x0, [fip], #8
	ldr	x1, [x0]
	br	x1
.endm
	#endif

.macro next
	b _NEXT
.endm

// ** Word flag bits
	.set	F_IMMEDIATE,	0x80
	.set	F_BUILTIN,	0x40
	.set	F_HIDDEN,	0x20
	.set	F_LEN_MASK,	0x1F

// ** Dictionary
// Dictionary format, 32 bytes- Note that this can't distinguish between words with identical lengths that are
//   also identical in the 1st 15 characters, but this gives us enough room in the dict to implement whatever
//   else we want later (hashed strings, symbol table entries, etc.)
// 0: [8b| Link word]            -> Points to link field of next word
// 1: [1b| Name len + flags]
//  : [7b| Name1]		 -> 1st 8 chars of name
// 2: [8b| Name2]		 -> 2nd 8 chars of name
// 3: [8b| Codeword]		 -> Addr of DOCOL (below) or a jump to the immediately following insn

	.set	dict_link, 0	// Dict terminator

.macro create_name label, qname, flags
.data
.align 3, 0
.global	name_\label

name_\label\():
	.quad	dict_link
	.set	dict_link, name_\label		// Link to previous word and update address
	.set	nlen_tempmacro_foo, (str_end_\label - str_\label)
	.byte	\flags | nlen_tempmacro_foo
str_\label\():
	.ascii	"\qname"
str_end_\label\():
.align 3, 0
.iflt	(nlen_tempmacro_foo - 8)
	.quad 0
.endif
.align 3, 0
.global \label
\label\():
	// Code word will follow
.endm

#define fw	.quad

// Define a new word in "Fith" - subsequent words should be .quad of the CFAs of the words called by this word, ie. the
// result of normal Fith compilation
.macro	defword	label, qname, flags=F_BUILTIN
	create_name	\label, "\qname", \flags
	// Fith execution codeword
	.quad	_DOCOL
.global	code_\label
data_\label:
.endm

// Define a new word in assembly - the CFA in this case just the address of the first asm insn in the word
// continue.
.macro	defcode	label, qname, flags=F_BUILTIN
	create_name	\label, "\qname", \flags
	// Asm execution codeword
	.quad	code_\label
.text
.global	code_\label
code_\label:
.endm

// Define a new variable
.macro defvar label, qname, initial=0, flags=F_BUILTIN
	create_name	\label, "\qname", \flags
	// Variable definition
	.quad	_DOVAR
.data
.align 3, 0
.global var_\label
var_\label:
	.quad	\initial
.endm

.macro	loadvar	reg, name
	ldr	scx0, =var_\name
	ldr	\reg, [scx0]
.endm

.macro	savevar name, reg
	ldr	scx0, =var_\name
	str	\reg, [scx0]
.endm

// Define a new constant
.macro defconst label, qname, value, flags=F_BUILTIN
	defcode \label, "\qname", \flags
	ldr	x0, =\value
	push	x0
	next
.endm

// The EXIT word is very important. It is what pops the return stack then resumes execution (via next)
defcode EXIT, "exit"
	poprsp	fip
	next

// *** Stack manipulation words ***
defcode	DROP, "drop"
	add	dsp, dsp, 8
	next

defcode DUP, "dup"
	ldr	x0, [dsp]
	push	x0
	next

defcode	OVER, "over"
	ldr	x0, [dsp, #8]
	push	x0
	next

defcode	SWAP, "swap"
	ldr	x0, [dsp, #8]
	ldr	x1, [dsp]
	str	x0, [dsp]
	str	x1, [dsp, #8]
	next

defcode	ROT, "rot"	// (a b c -- b c a)
	pop3	x2, x1, x0
	push3	x1, x0, x2
	next

defcode	NROT, "-rot"	// (a b c -- c a b)
	pop3	x2, x1, x0
	push3	x0, x2, x1
	next

// rotate the given word to the top of the stack (not counting current tos, ie. same convention as pick)
defcode ROLL, "roll"
	pop	x0

	lsl	x1, x0, #3
	add	x2, x1, dsp		// x2 = addr of new tos
	ldr	x5, [x2], #-8
	add	x3, x2, #8		// x2 = src x3 = dst
	b	2f

1:	ldr	x4, [x2], #-8		// ARM64 quirk - default for post-offset is to update reg; default for pre-offset is to NOT update reg
	str	x4, [x3], #-8		// +16 because we have already backed up by 8

2:	cmp	x3, dsp
	bne	1b

	str	x5, [dsp]
	next


defcode	NIP, "nip"	// (a b -- b)
	pop	x0
	str	x0, [dsp]
	next

defcode TUCK, "tuck"	// (a b -- b a b)
	pop2	x1, x0	// x1 = a, x0 = b
	push	x0	// (-- b)
	push2	x1, x0	// (-- b a b)
	next

defcode TWODROP, "2drop" // (a b -- a b a b)
	add	dsp, dsp, #16
	next

defcode TWODUP, "2dup" 	// (a b -- a b a b)
	ldr	x0, [dsp]
	ldr	x1, [dsp, #8]	// x0 = b x1 = a
	push2	x1, x0
	next

defcode	TWOSWAP, "2swap" // (a b c d -- c d a b)
	pop4	x0, x1, x2, x3
	push4	x2, x3, x0, x1
	next

defcode	TWOOVER, "2over" // (a b c d -- a b c d a b)
	ldr	x0, [dsp, #16]	// x0 = b
	ldr	x1, [dsp, #24]	// x1 = a
	push2	x1, x0
	next

defcode PICK, "pick"	// (a_m ... a_n ... a_0 n -- a_m ... a_n ... a_0 a_n) Dup the nth stack elem
	pop	x0
	ldr	x0, [dsp, x0, LSL #3]   // x1 = [dsp + (x0 * 8)]
	push	x0
	next

// (0 -- 0 | a -- a a)
defcode QDUP, "?dup"
	ldr	x0, [dsp]
	cbz	x0, 1f
	push	x0
1:	next

defcode TOR, ">r"
	pop	x0
	pushrsp	x0
	next

defcode	RFROM, "r>"	// (a --r: a)
	poprsp	x0
	push	x0
	next

defcode TWOTOR, "2>r"	// (a b --r: a b)
	pop2	x1, x0
	pushrsp	x1
	pushrsp	x0
	next

defcode TWORFROM, "2r>" // (r: a b -- a b)
	poprsp	x0
	poprsp	x1
	push2	x1, x0
	next

defcode	RFETCH, "r@"	// (r: a -- r: a a)
	ldr	x0, [rsp]
	push	x0
	next

defcode TWORFETCH, "2r@"	// (r: a b -- a b)
	ldr	x0, [rsp]
	ldr	x1, [rsp, #8]
	push2	x1, x0
	next

// These thoroughly nonstandard words speed up simple do-loops by knowing the
// fact that the loop infos are at the top of the rstack
// Probably simpler just to have an explicit cstack.
defcode LIDXFETCH, "lidxr@"	// (r: a b _ -- a b)
	ldr	x0, [rsp]
	ldr	x1, [rsp, #8]
	push2	x1, x0
	next

defcode LIDXSTORE, "lidxr!"	// ( a' b' --  r: a b _ -- r: a' b' _)
	pop2	x0, x1
	str	x1, [rsp]
	str	x0, [rsp, #8]
	next

defcode LINCRFETCH, "lincr@"	// ( -- incr r: incr a b _ )
	ldr	x0, [rsp, #16]
	push	x0
	next

// ( inc -- flag , expects a b _ on return stack, updates b by inc
defcode	LTEST, "looptest"
	mov	x0, #1
	b	looptest_impl

// ( inc -- flag , expects a b _ on return stack, updates b by inc
defcode	PLTEST, "+looptest"
	pop	x0

looptest_impl:
	ldr	x1, [rsp]
	ldr	x2, [rsp, #8]
	sub	x3, x1, x2		// index - limit
	movz	x4, #0x8000, lsl #48	// x4 = minint64_t
	add	x3, x3, x4		// (index - limit) + minint
	adds	x5, x0, x3		// If this overflows, the loop condition is met
	csetm	x6, vs			// vs = oVerflow flag Set
	add	x0, x0, x1		// New index
	str	x0, [rsp]
	push	x6
	next

// ( r: lj bj li bi ret )
defcode	IIMPL, "i"
	ldr	x0, [rsp]
	push	x0
	next

// ( r: lj bj li bi ret )
defcode	JIMPL, "j"
	ldr	x0, [rsp, #16]
	push	x0
	next

defcode	RDROP, "rdrop"	// (r: a --)
	add	rsp, rsp, #8
	next

defcode TWORDROP, "2rdrop"
	add	rsp, rsp, #16
	next

// *** Arithmetic ops
defcode INC, "1+"	// (a -- a+1)
	ldr	x0, [dsp]
	add	x0, x0, #1
	str	x0, [dsp]
	next

defcode DEC, "1-"	// (a -- a-1)
	ldr	x0, [dsp]
	sub	x0, x0, #1
	str	x0, [dsp]
	next

defcode INCX2, "2+"	// (a -- a+2)
	ldr	x0, [dsp]
	add	x0, x0, #2
	str	x0, [dsp]
	next

defcode DECX2, "2-"	// (a -- a-2)
	ldr	x0, [dsp]
	sub	x0, x0, #2
	str	x0, [dsp]
	next

defcode INCX4, "4+"	// (a -- a+4)
	ldr	x0, [dsp]
	add	x0, x0, #4
	str	x0, [dsp]
	next

defcode DECX4, "4-"	// (a -- a-4)
	ldr	x0, [dsp]
	sub	x0, x0, #4
	str	x0, [dsp]
	next

defcode INCX8, "8+"	// (a -- a+8)
	ldr	x0, [dsp]
	add	x0, x0, #8
	str	x0, [dsp]
	next

defcode DECX8, "8-"	// (a -- a-1)
	ldr	x0, [dsp]
	sub	x0, x0, #8
	str	x0, [dsp]
	next

defcode ADD, "+"	// (a b -- a + b)
	pop2	x1, x0
	add	x0, x1, x0
	push	x0
	next

defcode SUB, "-"	// (a b -- a - b)
	pop2	x1, x0
	sub	x0, x1, x0
	push	x0
	next

defcode MUL2, "2*"	// (a -- a * 2)
	pop	x0
	lsl	x0, x0, #1
	push	x0
	next

defcode	DIV2, "2/"	// (a -- a / 2)
	pop	x0
	asr	x0, x0, #1
	push	x0
	next

defcode MUL4, "4*"	// (a -- a * 2)
	pop	x0
	lsl	x0, x0, #2
	push	x0
	next

defcode	DIV4, "4/"	// (a -- a / 2)
	pop	x0
	asr	x0, x0, #2
	push	x0
	next

defcode MUL8, "8*"	// (a -- a * 2)
	pop	x0
	lsl	x0, x0, #3
	push	x0
	next

defcode	DIV8, "8/"	// (a -- a / 2)
	pop	x0
	asr	x0, x0, #3
	push	x0
	next

defcode	UMUL, "u*"	// (a b -- a * b)
	pop2	x1, x0
	mul	x2, x1, x0
	push	x2
	next

defcode	MUL, "*"	// (a b -- a * b)
	pop2	x1, x0
	mul	x2, x1, x0
	push	x2
	next

defcode	MMUL, "m*"	// (a b -- d)
	pop2	x1, x0
	mul	x3, x1, x0
	smulh	x2, x1, x0
	push2	x2, x3
	next

defcode	UMMUL, "um*"	// (a b -- d)
	pop2	x1, x0
	mul	x3, x1, x0
	umulh	x2, x1, x0
	push2	x2, x3
	next

// This is signed division - not sure if the default / should be signed or unsigned
defcode DIV, "/"
	pop2	x1, x0
	sdiv	x2, x1, x0
	push	x2
	next

// Arm doesn't have that nice /mod insn like Intel, so we do it the old fashioned way: n mod m = n - (n / m * m)
defcode	MOD, "mod"
	pop2	x1, x0		// (a b --) x1 = a x0 = b
	sdiv	x2, x1, x0	// x2 = a / b
	mul	x3, x2, x0
	sub	x0, x1, x3
	push	x0
	next

defcode	DIVMOD, "/mod"	// (a b -- a%b a/b)
	pop2	x1, x0
	sdiv	x2, x1, x0
	mul	x3, x2, x0
	sub	x0, x1, x3
	push2	x0, x2
	next

// Unsigned division
defcode UDIV, "u/"
	pop2	x1, x0
	udiv	x2, x1, x0
	push	x2
	next

// Arm doesn't have that nice /mod insn like Intel, so we do it the old fashioned way: n mod m = n - (n / m * m)
defcode	UMOD, "umod"
	pop2	x1, x0		// (a b --) x1 = a x0 = b
	udiv	x2, x1, x0	// x2 = a / b
	mul	x3, x2, x0
	sub	x0, x1, x3
	push	x0
	next

defcode	UDIVMOD, "u/mod"	// (a b -- a%b a/b)
	pop2	x1, x0
	udiv	x2, x1, x0
	mul	x3, x2, x0
	sub	x0, x1, x3
	push2	x0, x2
	next

defcode	LSHIFT, "lshift"	// (a b -- a << b)
	pop2	x1, x0
	lsl	x0, x1, x0
	push	x0
	next

// LOGICAL shift right, not arithmetic, does not propagate sign bit
defcode	RSHIFT, "rshift"	// (a b -- a >> b)
	pop2	x1, x0
	lsr	x0, x1, x0
	push	x0
	next

// ARITHMETIC shift right, propagates sign bit
defcode	RSHIFTA, "rshifta"	// (a b -- a >> b)
	pop2	x1, x0
	asr	x0, x1, x0
	push	x0
	next

defcode NEGATE, "negate"
	ldr	x0, [dsp]
	neg	x0, x0
	str	x0, [dsp]
	next

defcode	INVERT, "invert"
	ldr	x0, [dsp]
	eon	x0, x0, xzr
	str	x0, [dsp]
	next

defcode	AND, "and"
	pop2	x1, x0
	and	x0, x1, x0
	push	x0
	next

defcode	OR, "or"
	pop2	x1, x0
	orr	x0, x1, x0
	push	x0
	next

defcode	XOR, "xor"
	pop2	x1, x0
	eor	x0, x1, x0
	push	x0
	next

defcode	ABS, "abs"
	pop	x0
	cmp	xzr, x0
	csneg	x1, x0, x0, lt
	push	x1
	next

// *** Double words
// ( d n -- n1 n2 ) 128 bit narrowing divide - d = hi lo   n = divisor  n1 = remain n2 = quot
defcode UMDIVMOD, "um/mod"
	pop3	x1, x0, x2
	call	umdivmod_impl
	push2	x8, x0
	next

umdivmod_impl:
	// arm64 does not have a 128b narrowing divide like amd64.
	//   Algorithm and code taken from https://github.com/ridiculousfish/libdivide/blob/master/doc/divlu.c
	cmp	x0, x2
	bhs	1f

	clz	x8, x2
	lsl	x9, x2, x8
	lsl	x10, x0, x8
	neg	w11, w8
	lsr	x11, x1, x11
	cmp	x8, #0
	csel	x11, xzr, x11, eq
	orr	x10, x11, x10
	lsl	x11, x1, x8
	lsr	x12, x9, #32
	udiv	x13, x10, x12
	msub	w14, w13, w12, w10
	and	x15, x9, #0xffffffff
	mul	x16, x13, x15
	extr	x14, x14, x11, #32
	subs	x17, x16, x14
	cmp	x17, x9
	mov	x17, #-2
	cinc	x17, x17, ls
	cmp	x16, x14
	csel	x14, x17, xzr, hi
	add	x13, x14, x13
	extr	x10, x10, x11, #32
	and	x14, x13, #0xffffffff
	msub	x10, x14, x9, x10
	udiv	x14, x10, x12
	msub	w12, w14, w12, w10
	mul	x15, x14, x15
	mov	x16, x11
	bfi	x16, x12, #32, #32
	subs	x12, x15, x16
	cmp	x12, x9
	mov	w12, #-2
	cinc	w12, w12, ls
	cmp	x15, x16
	csel	w12, w12, wzr, hi
	add	w12, w12, w14
	bfi	x11, x10, #32, #32
	msub	x9, x12, x9, x11
	lsr	x8, x9, x8
	orr	x0, x12, x13, lsl #32
	ret

1:	mov	x0, #-1
	mov	x8, #-1
	ret

defcode SMREM, "sm/rem"
	pop3	x1, x0, x2

	// x9 == resulting sign of division
	eor	x9, x0, x2
	mov	x10, #-1
	lsr	x10, x10, 1
	and	x9, x9, x10

	and	x0, x0, x10
	and	x2, x2, x10

	call	umdivmod_impl
	orr	x0, x0, x10

	push2	x8, x0
	next

// ( d1 d2 -- d3 )  Each double is lo hi on the stack so eg x1 = hi part of 1st d
defcode DADD, "d+"
	pop4	x0, x1, x2, x3
	adds	x5, x0, x2
	adc	x6, x1, x3
	push2	x5, x6
	next

// Equivalent to "POP" on 2s compliment machines. I have never encountered a 1s or other complement anything.
defcode DTOS, "d>s"
	add	dsp, dsp, #8
	next

defcode	DNEGATE, "dnegate"
	pop2	x0, x1
dnegate_impl:
	subs	x2, xzr, x0
	sbc	x3, xzr, x1
	push2	x2, x3
	next

// ( d1 n -- d2 )	where d2 shares sign with N
defcode DPLUSMINUS, "d+-"
	pop3	x0, x1, x2
	eor	x3, x1, x2	// x3 < 0 when d1 needs negating
	cmp	x3, xzr
	blt	dnegate_impl
	push2	x0, x1
	next

defword	DABS, "dabs"
	fw	LIT, 10		// Arbitrary as long as it's positive
	fw	DPLUSMINUS
	fw	EXIT

// *** Booleans & comparison
defcode	TRUE, "true"
	mvn	x0, xzr
	push	x0
	next

defcode	FALSE, "false"
	mov	x0, xzr
	push	x0
	next

.macro	defcnd	label, qname, cond
	defcode	\label, "\qname"
	pop2	x1, x0
	cmp	x1, x0
	csetm	x0, \cond
	push	x0
	next
.endm

.macro	defzcnd	label, qname, cond
	defcode	\label, "\qname"
	pop	x0
	cmp	x0, xzr
	csetm	x0, \cond
	push	x0
	next
.endm

defcnd	EQ, "=", eq
defcnd	NEQ, "<>", ne
defcnd	LT, "<", lt
defcnd	GT, ">", gt
defcnd	LEQ, "<=", le
defcnd	GEQ, ">=", ge
defcnd	ULT, "u<", lo
defcnd	UGT, "u>", hi
defcnd	ULEQ, "u<=", ls
defcnd	UGEQ, "u>=", hs

defzcnd	ZEQ, "0=", eq
defzcnd	ZNEQ, "0<>", ne
defzcnd	ZLT, "0<", lt
defzcnd	ZGT, "0>", gt
defzcnd	ZLEQ, "0<=", le
defzcnd	ZGEQ, "0>=", ge

// ( a b -- a|b ) Return whichever of a or b is smaller (signed)
defcode MIN, "min"
	pop2	x0, x1
	cmp	x0, x1
	csel	x2, x0, x1, lt
	push	x2
	next

// Same as min, unsigned
defcode UMIN, "umin"
	pop2	x0, x1
	cmp	x0, x1
	csel	x2, x0, x1, lo
	push	x2
	next

// (t p q -- flag)	Test if t is within p and q, that is, p <= t < q.
// This is a little more complicated than it seems, because the standard says that:
// a) It has to work for signed AND unsigned numbers (but not testing signed vs. unsigned or vice versa, they all must be the same type)
// b) They have to work consistently when the comparison range straddles the wrapping boundary of the max cell size.
// The standard impl is:
// : WITHIN ( test low high -- flag ) OVER - >R - R> U< ;
defcode	WITHIN, "within"
	pop3	x0, x1, x2		// x0 = test, x1 = low, x2 = high
	call	within_impl
	push	x0
	next

within_impl:
	sub	x3, x2, x1		// x3 = high - low
	sub	x4, x0, x1		// x4 = test - low
	cmp	x4, x3			// x3 < x4?
	csetm	x0, lo			// lo = cc flag clear, unsigned <
	ret

// *** Branching
defcode BRANCH, "branch"
	ldr	x1, [fip]
	add	fip, fip, x1
	next

defcode SBRANCH, "sbranch"		// Just a branch with a different name so we can detect string literals on disassembly
	ldr	x1, [fip]
	add	fip, fip, x1
	next

defcode	ZBRANCH, "0branch"
	pop	x0
	cmp	x0, xzr
	beq	code_BRANCH		// Jump to BRANCH if x0 = 0
	add	fip, fip, #8		// Otherwise skip the offset
	next

// *** Memory access
defcode	STORE, "!"		// (v addr --) *addr = v
	pop2	x1, x0
	str	x1, [x0]
	next

defcode CSTORE, "c!"		// (v addr --) *(u8 *)addr = v & 0xFF
	pop2	x1, x0
	strb	w1, [x0]
	next

defcode WSTORE, "w!"		// (v addr --) *(u16 *)addr = v & 0xFFFF
	pop2	x1, x0
	strh	w1, [x0]
	next

defcode LSTORE, "l!"		// (v addr --) *(u32 *)addr = v & 0xFFFFFFFF
	pop2	x1, x0
	str	w1, [x0]
	next

defcode PLUSSTORE, "+!"		// (n addr --) *addr += n
	pop2	x1, x0
	ldr	x2, [x0]
	add	x2, x2, x1
	str	x2, [x0]
	next

defcode SUBSTORE, "-!"
	pop2	x1, x0
	ldr	x2, [x0]
	sub	x2, x2, x1
	str	x2, [x0]
	next

defcode	FETCH, "@"	// (addr -- v) v = *addr
	pop	x0
	ldr	x1, [x0]
	push	x1
	next

defcode	CFETCH, "c@"	// (addr -- v) v = *(byte *)addr
	pop	x0
	ldrb	w1, [x0]
	push	x1
	next

defcode	WFETCH, "w@"	// (addr -- v) v = *(short *)addr
	pop	x0
	ldrh	w1, [x0]
	push	x1
	next

defcode	LFETCH, "l@"	// (addr -- v) v = *(long *)addr
	pop	x0
	ldr	w1, [x0]
	push	x1
	next

defcode	LIT, "lit"	// ( -- *fip )
	ldr	x0, [fip], #8
	push	x0
	next

// This is essentially memcpy. It relies on the reasonable(?) sounding assumption
// that on arm64 w/no unaligned address exceptions enabled, a larger unaligned load or
// store is still faster than n byte fetches or stores. Based on a dumb translation of
// guthub.com/ClickHouse/ClickHouse/memcpy.h; DOES NOT HANDLE OVERLAPPING SRC
// AND DST CORRECTLY
defcode	MOVE, "move"	// (srcaddr dstaddr u --)	Move u address units from srcaddr to dstaddr.
#ifndef OPTIMIZED_MOVE
	pop3	x0, x1, x2

1:	cmp	x2, xzr
	beq	0f

	ldrb	w8, [x0], #1
	strb	w8, [x1], #1
	sub	x2, x2, #1
	b	1b
	next

#else
	pop3	x0, x1, x2

tail:
	// Small size?
	cmp	x2, #16
	bhi	medsize

	// Copy small sizes using one fetch and one (overlapping, if u is not an exact pw2) store
	cmp	x2, #8
	blo	wordsize

	// Copy last 8 bytes
	sub	x2, x2, 8
	ldr	x8, [x0, x2]
	str	x8, [x1, x2]
	// 1st 8 bytes (will overwrite some number of bytes we already copied)
	ldr	x9, [x0]
	str	x9, [x1]
	b	0f

wordsize:
	cmp	x2, #4
	blo	halfsize

	// Copy last 4 bytes
	sub	x2, x2, 4
	ldr	w8, [x0, x2]
	str	w8, [x1, x2]
	// 1st 4 bytes
	ldr	w9, [x0]
	str	w9, [x1]
	b	0f

halfsize:
	cmp	x2, #2
	blo	bytesize

	// Copy last 2 bytes
	sub	x2, x2, 2
	ldrh	w8, [x0, x2]
	strh	w8, [x1, x2]
	// 1st 2 bytes
	ldrh	w9, [x0]
	strh	w9, [x1]
	b	0f

bytesize:
	cmp	x2, #1
	blo	done
	ldrb	w8, [x0]
	strb	w8, [x1]
	b	0f

	// Large enough to loop, not large enough to care too much about dst alignment
medsize:
	cmp	x2, #128
	bhi	large_size

	// Copy last 8 bytes
	sub	x2, x2, 8
	ldr	x8, [x0, x2]
	str	x8, [x1, x2]

	// Copy remaining dwords
medloop:
	ldr	x8, [x0], #8
	str	x8, [x1], #8
	sub	x2, x2, 8
	bhs	medloop
	b	0f

large_size:
	// Copy the first < 15 bytes unaligned, to align dest to 16 bytes so we can use ldp / stp
	mov	x8, #16
	and	x9, x1, #0xF
	sub	x8, x8, x9	// 16 - (dst & 15)
	and	x8, x8, #0xF	// (16 - (dst & 15)) & 15
	beq	aligned

	cmp	x8, #8
	blt	byte_corr

	// padding is > 8 bytes
	ldr	x4, [x0], #8
	str	x4, [x1], #8
	sub	x2, #8
	sub	x8, #8
	bne	aligned

byte_corr:
	ldr	x4, [x0]
	str	x4, [x1]
	add	x0, x0, x8
	add	x1, x1, x8

aligned:
	// Destination address is now aligned to 16 bytes - verify
	tst	x4, 0xF
	beq	unrolled
	mov	x0, =bad_move_dest_alignment
	b	fith_abort

unrolled:
	ldr	x10, [x0], #8
	ldr	x11, [x0], #8
	stp	x10, x11, [x1], #16

	ldr	x12, [x0], #8
	ldr	x13, [x0], #8
	stp	x12, x13, [x1], #16

	ldr	x14, [x0], #8
	ldr	x15, [x0], #8
	stp	x14, x15, [x1], #16

	ldr	x16, [x0], #8
	ldr	x17, [x0], #8
	stp	x16, x17, [x1], #16

	ldr	x10, [x0], #8
	ldr	x11, [x0], #8
	stp	x10, x11, [x1], #16

	ldr	x12, [x0], #8
	ldr	x13, [x0], #8
	stp	x12, x13, [x1], #16

	ldr	x14, [x0], #8
	ldr	x15, [x0], #8
	stp	x14, x15, [x1], #16

	ldr	x16, [x0], #8
	ldr	x17, [x0], #8
	stp	x16, x17, [x1], #16

	sub	x2, x2, #128
	blo	tail				// Final < 128 bytes is handled by the upper routines
	b	unrolled
#endif

0:	next

// Uses move, as implemented in the Forth 20xx standard
defcode	CMOVE, "cmove"	// (fromaddr toaddr u --)	for i in 0 .. u	toaddr[i] = fromaddr[i]
	pop3	x0, x1, x2

1:	cmp	x2, #0
	beq	2f

	ldrb	w8, [x0], #1
	strb	w8, [x1], #1
	sub	x2, x2, #1
	b	1b

2:	next

// ( c-addr u char -- ) Fill u bytes of memory starting at c-addr with char. Optimized to do word fills until < 8 bytes remain
// but does not check starting alignment.
defcode FILL, "fill"
	pop3	x0, x1, x2

	cmp	x1, xzr
	ble	3f

	cmp	x1, #8
	mov	x3, x1
	blt	2f

	// Replicate low byte of x2 into all 8 bytes of x4
	and	w4, w2, #0xFF		// 00000000000000xx
	orr	x5, x4, x4, LSL #8
	orr	x6, x5, x5, LSL #16
	orr	x4, x6, x6, LSL #32

	and	x3, x1, #7	// Mask off lower 3 bits, must write these as bytes
	lsr	x1, x1, #3

1:	cmp	x1, xzr
	ble	2f

	str	x4, [x0], #8
	sub	x1, x1, #1
	b	1b

2:	cmp	x3, xzr
	ble	3f

	strb	w2, [x0], #1
	sub	x3, x3, #1
	b	2b

3:	next

defcode	DSPFETCH, "dsp@"
	mov	x0, dsp
	push	x0
	next

defcode	DSPSTORE, "dsp!"
	pop	x0
	mov	dsp, x0
	next

// ( -- addr-s addr-base capacity ) - note: addr-s points to the tos on ENTRY to this word
defcode STACK, "stack"
	mov	x0, dsp
	loadvar	x1, S0
	ldr	x2, =data_stack_top
	ldr	x3, =data_stack
	sub	x2, x2, x3
	push3	x0, x1, x2
	next

defcode	RSPFETCH, "rsp@"
	push	rsp
	next

defcode RSPSTORE, "rsp!"
	pop	rsp
	next

// ( -- addr-s addr-base capacity ) - note: addr-s points to the tos on ENTRY to this word
defcode RSTACK, "rstack"
	mov	x0, rsp
	loadvar	x1, R0
	ldr	x2, =return_stack_top
	ldr	x3, =return_stack
	sub	x2, x2, x3
	push3	x0, x1, x2
	next

defword	HERE, "here"
	fw	CP
	fw	FETCH
	fw	EXIT

defword ALLOT, "allot"
	fw	CP
	fw	PLUSSTORE
	fw	EXIT

defcode ALIGN, "align"
	loadvar	x0, CP
	add	x1, x0, #7
	bic	x2, x1, #7
	savevar	CP, x2
	next

defcode ALIGN16, "align16"
	loadvar	x0, CP
	add	x1, x0, #15
	bic	x2, x1, #15
	savevar	CP, x2
	next

defcode ALIGN32, "align32"
	loadvar	x0, CP
	add	x1, x0, #31
	bic	x2, x1, #31
	savevar	CP, x2
	next

defcode ALIGNED, "aligned"
	pop	x0
	add	x1, x0, #7
	bic	x2, x1, #7
	push	x2
	next

// ( v addr -- aaddr )  Align addr by advancing it such that the lower v bits are clear.
defcode	NUMALIGNED, "#aligned"
	pop2	x1, x0
	mov	x2, #1
	lsl	x2, x2, x1	// (1 << v) - 1
	sub	x2, x2, #1
	add	x0, x0, x2
	bic	x0, x0, x2
	push	x0
	next

// (lfa -- cfa) Given a link field address of a dict word, convert that into a code field address ** DICT LAYOUT DEPENDENCY
defcode TOCFA, ">cfa"
	pop	x0
	add	x0, x0, #24	// 3 words
	push	x0
	next

// (cfa -- lfa) Given a CFA / xt of a word, move to its link field address
defcode CFAFROM, "cfa>"
	pop	x0
	sub	x0, x0, #24	// 3 words
	push	x0
	next

// ( cfa -- data ) Given the CFA of a word, move to the data (body) field
defcode TOBODY, ">body"
	pop	x0
	add	x0, x0, #8
	push	x0
	next

defcode BODYFROM, "body>"
	pop	x0
	sub	x0, x0, #8
	push	x0
	next

defcode XTTONT, "xt>nt"
	pop	x0
	sub	x0, x0, #16
	push	x0
	next

defword NAMETOCOMPILE, "name>compile"
	fw	LIT, 16, ADD
	fw	EXIT

defword NAMETOINTERPRET, "name>interpret"
	fw	LIT, 16, ADD
	fw	EXIT

// ( nt -- caddr u )
defword	NAMETOSTRING, "name>string"
	fw	DUP, CFETCH, LIT, F_LEN_MASK, AND
	fw	SWAP, INC, SWAP
	fw	EXIT

// *** Compilation misc.
defcode	CELLS, "cells"
	pop	x1
	lsl	x0, x1, #3
	push	x0
	next

defword	CELLPLUS, "cell+"
	fw	LIT, 1
	fw	CELLS
	fw	ADD
	fw	EXIT

defword COMMA, ","
	fw	HERE
	fw	LIT, 8
	fw	ALLOT
	fw	STORE
	fw	EXIT

defword CCOMMA, "c,"
	fw	HERE
	fw	LIT, 1
	fw	ALLOT
	fw	CSTORE
	fw	EXIT

defword LITERAL, "literal", F_IMMEDIATE | F_BUILTIN
	fw	LIT, LIT	// Well that's fun
	fw	COMMA, COMMA	// COMMA COMMA COMMA CHAMELEON
	fw	EXIT

defword BRA, "[", F_IMMEDIATE | F_BUILTIN
	fw	LIT, 0
	fw	STATE
	fw	STORE
	fw	EXIT

defword KET, "]"
	fw	LIT, 1
	fw	STATE
	fw	STORE
	fw	EXIT

defcode TTICK, "''"
	ldr	x1, [fip], #8
	push	x1
	next

// ( addr u -- ) Create dict entry for word on stack
defword STARCREATE, "*create"
	fw	HERE, DUP, TOR
	fw	LIT, 32, LIT, 0, FILL

	//	Link word
	fw	GETCURRENT, FETCH
	fw	COMMA			// Link field

	//	nameptr - 1st name word
	// Name len byte
	fw	DUP			// ( addr u u )
	fw	DEFFLAG, FETCH
	fw	OR
	fw	CCOMMA			// ( addr u )

	// Name words
	fw	LIT, 15			// Max len of name
	fw	MIN			// ( addr u|15 )
	fw	HERE
	fw	SWAP			// ( addr here u|15 )
	fw	CMOVE

	// Align, then skip an extra word if the name was short
	fw	ALIGN

	fw	HERE, RFETCH, SUB
	fw	LIT, 24, LT

	fw	ZBRANCH
	fw	1f - .

	fw	LIT, 1,	CELLS
	fw	ALLOT

	// Code field
1:	fw	LIT, _DOVAR
	fw	COMMA

	// Update last
	fw	RFROM
	fw	GETCURRENT, STORE
	fw	EXIT

defword	CREATE, "create"
	fw	ALIGN
	fw	PARSEWORD
	fw	STARCREATE
	fw	EXIT

defword COLON, ":"
	fw	CREATE
	fw	LIT, _DOCOL	// Change the cfa of the word just created to _DOCOL from _DOVAR
	fw	HERE, BODYFROM
	fw	STORE
	fw	TOGGLEHIDELATEST
	fw	KET
	fw	EXIT

defword	SEMIC, ";", F_IMMEDIATE | F_BUILTIN
	fw	LIT, EXIT
	fw	COMMA
	fw	BRA
	fw	TOGGLEHIDELATEST
	fw	EXIT

// Given the lfa of a word, move to its name
defcode TONAME, ">name"
	pop	x0
	add	x1, x0, #8
	push	x1
	next

// Given the name field of a word, move to its lfa
defcode NAMEFROM, "name>"
	pop	x0
	sub	x1, x0, #8
	push	x1
	next

defword LATEST, "latest"
	fw	GETCURRENT, FETCH
	fw	EXIT

defword LASTNAME, "last-name"
	fw	GETCURRENT, FETCH
	fw	TONAME
	fw	EXIT

// Toggle hidden bit on the dict entry at TOS
defcode TOGGLEHIDE, "toggle-hide"
	pop	x0
	add	x0, x0, #8	// Move to name field
	ldrb	w1, [x0]
	eor	w1, w1, #F_HIDDEN
	strb	w1, [x0]
	next

// Toggle hidden bit on the dict entry at TOS
defword TOGGLEHIDELATEST, "toggle-hide-latest"
	fw	LATEST
	fw	TOGGLEHIDE
	fw	EXIT

defword	IMMEDIATE, "immediate"
	fw	LASTNAME
	fw	DUP, CFETCH
	fw	LIT, F_IMMEDIATE
	fw	OR
	fw	SWAP, CSTORE
	fw	EXIT

// ( addr u -- ) Compile a string literal into the current word.
// This consists of:
// 	BRANCH
// 	(offset to T)
// 	(string) + (alignment)
// T:	LIT, addr
// 	LIT, u
defword SLITERAL, "sliteral", F_IMMEDIATE | F_BUILTIN
	fw	LIT, SBRANCH, COMMA	// compile branch
	fw	DUP			// addr u u
	fw	CELLPLUS		// addr u (u+8)
	fw	ALIGNED			// addr u (u+8 aligned)
	fw	COMMA			// Compile u+8 aligned (branch target)
	fw	HERE, SWAP		// addr here u
	fw	DUP, ALIGNED		// addr here u u'
	fw	ALLOT
	fw	OVER, LITERAL		// addr here u
	fw	DUP, LITERAL		// addr here u
	fw	CMOVE
	fw	EXIT

// ( char -- lchar )
defcode DOWNCASE, "downcase"
	pop	x12
	bl	downcase_impl
	push	x12
	next

downcase_impl:
	cmp	x12, #'A'
	blo	1f		// Less than A

	cmp	x12, #'Z'	// Greater than Z
	bhi	1f

	// Convert to lower case
	sub	x12, x12, #'A'
	add	x12, x12, #'a'

1:	ret

// ( addr1 u1 addr2 u2 -- 0 | 1 | -1 )
defcode COMPARE, "compare"
	pop4	x0, x1, x2, x3

	// Rules:
	//   Identical strings return 0
	//   Strings of different length that are identical up to the length of the shorter string
	//     return -1 if u1 is shorter than u2, otherwise 1
	//   Strings that differ return -1 if the first differing character from addr1 is < the
	//     char in addr2, 1 otherwise
cc_top:	cmp	x1, xzr
	bne	cc_leftmore

	cmp	x3, xzr
	bne	cc_rightmore			// Ran out of chrs at the same time

	// If we get here, the strings ran out at the same time so they're equal
	mov	x6, xzr
	b	cc_done

cc_rightmore:
	// Here, 1 was shorter than 2, but the strings were equal to this point. Return -1
	mov	x6, #-1
	b	cc_done

cc_leftmore:
	cmp	x3, xzr
	bne	cc_comparenext

	// Here, 2 was shorter than 1, but the strings were equal to this point. Return 1
	mov	x6, #1
	b	cc_done

cc_comparenext:
	// Both strings have new characters
	ldrb	w10, [x0], #1
	sub	x1, x1, #1

	ldrb	w11, [x2], #1
	sub	x3, x3, #1

	cmp	x10, x11
	beq	cc_top			// Equal chars, start again with the next

	blt	cc_firstlt

	// 1st higher, return 1
	mov	x6, #1
	b	cc_done

cc_firstlt:
	mov	x6, #-1

cc_done:
	push	x6
	next

// ( addr1 u1 addr2 u2 -- 0 | 1 | -1 )
defcode CICOMPARE, "cicompare"
	pop4	x0, x1, x2, x3

	// Rules:
	//   Identical strings return 0
	//   Strings of different length that are identical up to the length of the shorter string
	//     return -1 if u1 is shorter than u2, otherwise 1
	//   Strings that differ return -1 if the first differing character from addr1 is < the
	//     char in addr2, 1 otherwise
ci_top:	cmp	x1, xzr
	bne	ci_leftmore

	cmp	x3, xzr
	bne	ci_rightmore			// Ran out of chrs at the same time

	// If we get here, the strings ran out at the same time so they're equal
	mov	x6, xzr
	b	ci_done

ci_rightmore:
	// Here, 1 was shorter than 2, but the strings were equal to this point. Return -1
	mov	x6, #-1
	b	ci_done

ci_leftmore:
	cmp	x3, xzr
	bne	ci_comparenext

	// Here, 2 was shorter than 1, but the strings were equal to this point. Return 1
	mov	x6, #1
	b	ci_done

ci_comparenext:
	// Both strings have new characters
	ldrb	w12, [x0], #1
	bl	downcase_impl
	mov	x10, x12
	sub	x1, x1, #1

	ldrb	w12, [x2], #1
	bl	downcase_impl
	mov	x11, x12
	sub	x3, x3, #1

	cmp	x10, x11
	beq	ci_top			// Equal chars, start again with the next

	blt	ci_firstlt

	// 1st higher, return 1
	mov	x6, #1
	b	ci_done

ci_firstlt:
	mov	x6, #-1

ci_done:
	push	x6
	next

// ( addr u -- ) 	Given a FCS, translate any upper case letters to lower case. Note: In place. Note note: Ascii only. Note note note: lame.
defcode	FSTOLOWER, "fstolower"
	pop2	x0, x1
	call	fstolower_impl
	next

fstolower_impl:
1:	cmp	x1, xzr
	ble	2f

	// Fetch next chr
	ldrb	w2, [x0], #1
	sub	x1, x1, #1

	cmp	x2, #'A'
	blo	1b		// Less than A

	cmp	x2, #'Z'	// Greater than Z
	bhi	1b

	// Convert to lower case
	sub	x2, x2, #'A'
	add	x2, x2, #'a'
	strb	w2, [x0, #-1]
	b	1b

2:	ret

// ( addr -- ) 	Given a SCS, translate any upper case letters to lower case. Note: In place. Note note: Ascii only. Note note note: lame.
defcode	STOLOWER, "stolower"
	pop	x0
	call	stolower_impl
	next

stolower_impl:
	ldrb	w1, [x0], #1
	b	fstolower_impl

// To short counted string, also zeros to next word boundary making it compatible with our name field tests
// in word matching.
// ( caddr caddr u -- ) Takes dest, src, len -- makes a short counted string at dest
defcode	TOSCS, "$toscs"
	pop3	x0, x1, x2
	call	toscs_impl
	next

toscs_impl:
	strb	w2, [x0], #1	// Store length byte

1:	cmp	x2, xzr
	beq	2f

	ldrb	w3, [x1], #1
	strb	w3, [x0], #1
	sub	x2, x2, #1
	b	1b

	// Clear to start of next full word
2:	ands	x3, x0, #0xF
	beq	3f
	strb	wzr, [x0], #1
	b	2b

3:	ret

defcode NTELL, "#ntell"
	pop	x0
	call	ntell_impl
	next

ntell_impl:
	mov	scx0, x0
	ldrb	scw1, [scx0], #1
	// Mask flags
	and	scx1, scx1, #0x1f

1:	cmp	scx1, xzr
	ble	2f

	ldrb	w0, [scx0], #1
	call	uart_putb
	sub	scx1, scx1, #1
	b	1b
2:	ret

// Note: caddrs here are SCS
// ( caddr caddr lfa --		lowered normal len lfa --
// 	caddr caddr lfa 0  		- No match
// 	caddr caddr 0   0 true	- End of list
// 	caddr caddr xt 1|-1 true	- Match
// )
// Check to see if the word at lfa matches the name given. If it does, return 1 if the word isn't immediate or -1 if it is
defcode	MATCHXT, "matchxt"
	pop3	x2, x1, x0

.global matchxt_impl
matchxt_impl:
	// If lfa is null, we hit the end of the list
	cmp	x0, xzr
	bne	1f

	push4	x2, x1, xzr, xzr
	mov	x11, #-1
	push	x11
	b	5f

	// Use lower buf if this is a builtin word, otherwise normal buf
1:	ldrb	w9, [x0, #8]
	mov	x12, x9
	tst	w9, F_BUILTIN
	csel	x10, x2, x1, ne
	and	x9, x9, #0x1f

#if 1
	loadvar	x15, VERBOSE
	cmp	x15, xzr
	beq	6f

	// Print test : dict
	mov	scx3, x0
	mov	scx4, x1
	mov	scx5, x2
	mov	scx2, x10

	mov	x0, x10
	call	ntell_impl

	mov	x0, #':'
	call	uart_putc

	mov	x0, #' '
	call	uart_putc

	mov	x0, scx3
	add	x0, x0, #8	// Skip to name word
	call	ntell_impl
	call	cr_impl

	mov	x10, scx2
	mov	x2, scx5
	mov	x1, scx4
	mov	x0, scx3
	/////////
#endif

	// Fetch first comparison words - will be at the word after the lfa
6:	ldr	x3, [x10]
	ldr	x4, [x0, #8]

	// Mask flags from the first comparison word (because we're little endian, this is actually in the low byte
	// of the reg even though it's first in memory). Note that we don't mask F_HIDDEN. This has the net effect that
	// hidden names will never match the count of the search word, and will therefore never be found
	movn	x8, #(F_IMMEDIATE | F_BUILTIN)
	and	x7, x4, x8
	cmp	x7, x3
	bne	4f		// No match

	// Skip comparing second word if 1st is short
	cmp	x9, #7
	bls	2f

	// Check second word - faster to check than take a branch? Maybe not, since we have to fetch the next word
	ldr	x5, [x10, #8]
	ldr	x6, [x0, #16]
	cmp	x5, x6
	bne	4f		// No match

	// Match! Check if it's immediate
matchxt_matched:
2:	mov	scx0, #-1
	mov	scx1, #1
	tst	x12, #F_IMMEDIATE
	csel	x3, scx1, scx0, ne

3:	add	x0, x0, #24		// Move to the nt of this word

	push3	x2, x1, x0
	push	x3
	mov	x11, #-1
	push	x11
	b	5f

4:	push4	x2, x1, x0, xzr

5:	next

// ( ... xt wlst -- ... )
defword	EXECWORDLIST, "exec-wordlist"
	fw	SWAP, TOR	// ( lfa r: xt )
1:	fw	FETCH		// ( lfa )
	fw	RFETCH		// ( lfa xt )
	fw	EXECUTE		// ( ... x )
	fw	ZBRANCH
	fw	1b - .
	fw	RFROM, DROP	// ( r: )
	fw	EXIT

// Search the given wordlist for the FCS
// ( caddr u wlst --
//	xt  1  - found immediate
//	xt -1  - found non immediate
// 	0      - not found )
defword	SEARCHWORDLIST, "search-wordlist"
	fw	TOR				// ( caddr u -- r: wlst )
	fw	TWODUP				// ( caddr u caddr u )
	fw	LIT, word_search_buffer		// ( caddr u caddr u dst )
	fw	DUP, TOR			// ( caddr u caddr u dst -- r: wlst normal_str )
	fw	NROT				// ( caddr u dst caddr u )
	fw	TOSCS				// ( caddr u )
	fw	LIT, word_lower_buffer		// ( caddr u dst )
	fw	DUP, TOR			// ( caddr u dst -- r: wlst normal_str lower_str )
	fw	NROT
	fw	TOSCS				// ( -- r: wlst normal_str lower_str )
	fw	RFROM, DUP			// ( lower_str lower_str -- r: wlst normal_str )
	fw	STOLOWER			// ( lower_str -- r: wlst normal_str )
	fw	RFROM, RFROM			// ( lower_str normal_str wlst )
	fw	LIT, MATCHXT			// ( lower_str normal_str wlst xt )
	fw	SWAP				// ( lower_str normal_str xt wlst )
	fw	EXECWORDLIST			// ( addr addr x x )
	fw	TWOSWAP, DROP, DROP		// ( x x )
	fw	QDUP, DROP
	fw	EXIT

// ( caddr uu -- 0 | xt 1 | xt -1 )
defword	FINDWORDCURRENT, "find-word-cur"
	fw	GETCURRENT
	fw	SEARCHWORDLIST
1:	fw	EXIT

defword FINDWORD, "find-word"
	fw	FINDWORDVEC, FETCH
	fw	EXECUTE
	fw	EXIT

word_search_buffer:	.space	256
word_lower_buffer:	.space	256

defword	REPL, "repl"
1:	fw	REFILL
	fw	ZBRANCH
	fw	1b - .
	fw	INTERPRETLINE
	fw	STATE, FETCH
	fw	LIT, 1, SUB
	fw	ZBRANCH
	fw	1b - .
	fw	LIT, ok_msg
	fw	LIT, ok_msg_len
	fw	TELL
	fw	BRANCH
	fw	1b - .
	fw	EXIT

.data
.align 3
ok_msg:	.ascii "Ok.\n"
	.equ	ok_msg_len, . - ok_msg

// **** Outer interpreter
// Repeat until the buffer is empty:
//   PARSEWORD - lex single word from input
//   FINDWORD  - Convert from string to exec token
//   QEXECUTE  - Exec (state == 0 | immediate word) / ?number / compile
defword	INTERPRETLINE, "interpretline"
.iword: fw	PARSEWORD	// caddr u
	fw	QDUP		// caddr u u?
	fw	ZBRANCH
	fw	.iexit - .
	fw	TWODUP		// caddr u caddr u
	fw	FINDWORD	// caddr u ( 0 | xt n )
	fw	QEXECUTE
	fw	BRANCH
	fw	.iword - .
.iexit: fw	DROP
	fw	EXIT

// ( caddr u 0 -- n )		push number
// ( caddr u xt n -- ... )	execute word
// if n != 0 then exec or compile
// otherwise ?number
defword QEXECUTE, "?execute"
	fw	QDUP
	fw	ZBRANCH
	fw	.qenumber -.
	// caddr u xt +-1
	fw	ROT, DROP
	fw	ROT, DROP	// ( xt +-1 )

	fw	ZLT
	fw	STATE, FETCH	// Compile if BOTH !immediate and compiling state
	fw	AND

	fw	ZBRANCH
	fw	.qeexec - .
	fw	COMMA
	fw	EXIT		// Compile and bail

.qeexec:
	fw	EXECUTE
	fw	EXIT		// Immediate

.qenumber:
	fw	QNUMBER
	fw	ZBRANCH
	fw	.qeabort - .	// Abort if not a number; unknown word

	fw	STATE, FETCH	// Compiling? Immediate = push num right now; compiling = compile LIT xxx
	fw	ZBRANCH
	fw	.eexit - .
	fw	LITERAL

.eexit: fw	EXIT

.qeabort:
	fw	LIT, noword_msg
	fw	LIT, noword_msg_len
	fw	TELL
	fw	TELL
	fw	LIT, '>', EMIT
	fw	CR
	fw	ABORT


.equ	USER_INPUT_ID,0
.equ	EVALUATE_ID,-1

// *** Low level input
// Input
defvar IB, "ib", default_input_buffer
defvar NUMIB, "#ib", 0
defvar TOIN, ">in", 0
defvar SOURCEID, "sourceid", 0

.global default_input_buffer
.global	word_buffer
.global pad_buffer
.global	line_buffer

.data
.align 4
default_input_buffer:
	.space	DEFAULT_INPUT_BUFFER_SIZE
	.equ	default_input_buffer_len, .-default_input_buffer

.align 4
word_buffer:
	.space	35
	.equ	word_buffer_len, .-word_buffer

.align 4
pad_buffer:
	.space	PAD_BUFFER_SIZE
	.equ	pad_buffer_len, .-pad_buffer

.align 4
line_buffer:
	.space	LINE_BUFFER_SIZE
	.equ	line_buffer_len, .-line_buffer

.text
defcode	SOURCE, "source"		// ( -- caddr u )
	loadvar	x0, IB
	loadvar	x1, NUMIB
	push2	x0, x1
	next

defcode SOURCE_ID, "source-id"		// ( -- 0 | -1 )
	// Hack warning.
	loadvar	x0, SOURCEID
	push	x0
	next

// ( u -- char flag ) If u is < #IB, char is IB[u]. Otherwise undefined. flag is whether or not char is valid.
// If false, u was beyond #IB and the value of char is undefined.
defcode INFETCH, "in@"
	pop	x0

	call	inch_impl

	push2	x0, x1
	next

	// In: x0 = >in, x1 = iblen, x2 = ibaddr
inch_impl:
	loadvar	x2, IB
	loadvar	x3, NUMIB

	cmp	x0, x3
	csetm	x1, lo
	ldrb	w0, [x2, x0]
1:	ret


// *** Parsing

// Increment >in unless that would put it past #ib
defcode	INPLUS, "in+"
	loadvar	x0, TOIN
	loadvar	x1, NUMIB

	add	x0, x0, #1

	cmp	x0, x1
	bhs	1f
	savevar	TOIN, x0

1:	next

// ( lo hi -- caddr u ) Parse a token from the current input source.

// Characters that are within base limit (as defined by the WITHIN word) make up
// the token, returned as a FCS on the stack. Because of the way WITHIN works:
// if lo < hi, characters between lo and hi will be included in the token.
// if hi < lo, characters between lo and hi will DELIMIT the token.
// In fith:
// : parse-token
//    >in @ dup >r -rot	( base limit -- inoff base limit, r: inoff )
//    2>r	( x -- inoff, r: inoff lo hi )
//    begin
//      dup inch  ( inoff -- inoff char flag )
//      swap 2r@  ( inoff char flag -- inoff flag char lo hi )
//      within	  ( inoff flag char lo hi -- inoff charvalid iswithin )
//      and	  ( inoff flag0 flag1 -- inoff flag )
//    0= while
//      1+	  ( >in' )
//    repeat

//    ( >in', r: >in lo hi )
//    dup >in !
//    r> drop r> drop	( >in', r: >in )
//    r@ - r>		( u >in )
//    source drop	( u >in inaddr )
//    + swap		( saddr u )
// ;
defcode	PARTOK, "parse-token"
	pop2	x11, x12

	loadvar	x10, TOIN
	mov	x13, x10	// Remember original >in

1:	mov	x0, x10
	call	inch_impl	// x0 = chr, x1 = valid
	cmp	x1, xzr
	beq	2f

	mov	x8, x0
	mov	x9, x1		// Save chr and flag

	mov	x1, x11
	mov	x2, x12
	call	within_impl

	ands	x0, x0, x9
	beq	2f		// 0 = done

	add	x10, x10, #1
	b	1b

2:	savevar	TOIN, x10
	sub	x1, x10, x13	// x1 = u

	loadvar	x0, IB
	add	x0, x0, x13

	push2	x0, x1
	next

// ( char -- caddr u ) Parse until next occurrence of char in input, or end
//   of input, then skip char. Return FCS of parsed line
defword	PARSE, "parse"
	fw	DUP
	fw	INC	// base limit
	fw	SWAP	// limit base
	fw	PARTOK
	fw	INPLUS
	fw	EXIT

// ( lo hi -- )	Skip all input chars between lo and hi via parse-token
defword	SKIP, "skip"
	fw	PARTOK
	fw	DROP, DROP
	fw	EXIT

// ( lo hi -- caddr u ) Skip until the first non ws, non cc character (ascii 0 .. 33) in the input,
// 	then collect characters until the first ws or cc character (ascii 0 .. 33)
defword PARSEWORD, "parse-word"
	fw	LIT, 0
	fw	LIT, 33
	fw	SKIP
	fw	LIT, 33
	fw	LIT, 0
	fw	PARTOK
	fw	INPLUS
	fw	EXIT

// ** Number conversion is hairy

// x0 = src x1 = end x2 = outptr
// Returns chr in x4, flag in x5
convertChar:
	// Empty string?
	cmp	x0, x1
	bcs	.falseRet

	ldrb	w4, [x0], 1	// Fetch chr
	cmp	x0, x1		// Room for closing tick?
	mov	x6, x4
	bhs	.falseRet

	ldrb	scw0, [x0], 1	// Check for '
	cmp	scw0, '\''
	bne	.falseRet

	cmp	x0, x1		// Flag x5 true if entire string consumed
	csetm	x5, eq
	b	.done

.falseRet:
	mov	x5, xzr
.done:
	ret

	// x5 = (x15 <= x4 < x16) ? -1 : 0
withinRange:
	sub	scx0, x16, x15		// s0 = high - low
	sub	scx1, x4, x15		// s1 = test - low
	cmp	scx1, scx0		// s0 < s1?
	csetm	x5, lo			// lo = cc flag clear, unsigned <
	ret

defword	GETCURRENT, "get-current"
	fw	CURRENT
	fw	FETCH
	fw	EXIT

// ( caddr u -- n true ) if convertible
// ( caddr u -- caddr u false ) if not convertible
// Convert the given FCS into a number if possible. Handles F20xx
// 	$[-]<hexnum>, #[-]<decnum>, %[-]<binnum>, 'C', and [-]<basenum>
defcode	QNUMBER, "?number"
	pop2	x0, x1

	// x10, copy of caddr; x11, copy of u
	mov	x10, x0
	mov	x11, x1
	mov	x12, xzr

	// x12, nonzero if the number is negative

	// x1 = last addr in word
	add	x1, x0, x1

	// zero len?
	cmp	x0, x1
	bhs	.notConvertible

	// x7 will be the base
	// x4 = current char

	// Check for ' as first char
	ldrb	w4, [x0], #1
	cmp	w4, #'\''
	bne	.notCharNum

	call	convertChar
	cmp	x5, #0
	beq	.notConvertible
	b	.convertible

.notCharNum:
	// Not a tick, check for one of the base overrides: % = binary, # = decimal, $ = hex
	cmp	x4, #'%'
	bne	.notBinary
	mov	x7, #2
	b	.loadNext

.notBinary:
	cmp	x4, #'#'
	bne	.notDecimal
	mov	x7, #10
	b	.loadNext

.notDecimal:
	cmp	x4, #'$'
	bne	.notHex
	mov	x7, #16

.loadNext:
	cmp	x0, x1
	bhs	.notConvertible
	ldrb	w4, [x0], #1
	b	.checkMinus

.notHex:
	loadvar	x7, BASE

.checkMinus:
	// x6 - the number we are building up
	mov	x6, xzr

	cmp	x4, '-'
	csetm	x12, eq		// x12 true if '-' symbol present
	bne	.handleDigit

	// Load next char and make sure there is one
	cmp	x0, x1
	bhs	.notConvertible

	ldrb	w4, [x0], #1

.handleDigit:
	// Convert x4 (current char) into a number: '0' - '9' -> 0..9, 'A' - 'Z' or 'a' - 'z' -> 10..25

	// Decimal digit?
	mov	x15, #'0'
	mov	x16, #'9' + 1
	call	withinRange
	cmp	x5, xzr
	beq	.notDecDigit

	sub	x4, x4, #'0'
	b	.gotDigit

.notDecDigit:
	// Upper case alphabetic?
	mov	x15, #'A'
	mov	x16, #'Z' + 1
	call	withinRange
	cmp	x5, xzr
	beq	.notAlphaDigit

	sub	x4, x4, #'A'
	add	x4, x4, #10
	b	.gotDigit

.notAlphaDigit:
	// Lower case alphabetic?
	mov	x15, #'a'
	mov	x16, #'z' + 1
	call	withinRange
	cmp	x5, xzr
	beq	.notConvertible

	sub	x4, x4, #'a'
	add	x4, x4, #10

.gotDigit:
	// Check for digit >= base
	cmp	x4, x7
	bhs	.notConvertible

	// Accumulate num
	madd	x6, x6, x7, x4		// Existing num * base + digit

	// Check if that was the last digit
	cmp	x0, x1
	beq	.convertible

	// Nope, load the next one
	ldrb	w4, [x0], #1
	b	.handleDigit

.convertible:
	cmp	x12, xzr
	beq	.positive
	neg	x6, x6

.positive:
	mov	x5, #-1
	push	x6
	b	.pushFlag

.notConvertible:
	mov	x5, xzr
	push2	x10, x11

.pushFlag:
	push	x5
	next

// ( -- r: ib #ib >in sid)		// Save the input state onto the return stack
defcode	SAVEINPUT, "save-input"
	loadvar	x0, IB
	loadvar x1, NUMIB
	loadvar x2, TOIN
	loadvar x3, SOURCEID

	pushrsp	x0
	pushrsp	x1
	pushrsp	x2
	pushrsp	x3
	next

// ( r: ib #ib >in sid -- r: )	// Restore the input state from the return stack
defcode	RESTOREINPUT, "restore-input"
	poprsp	x3
	poprsp	x2
	poprsp	x1
	poprsp	x0

	savevar	SOURCEID, x3
	savevar	TOIN, x2
	savevar	NUMIB, x1
	savevar	IB, x0
	next

// ( ib #ib >in id -- )		// Set the input state to >in, #ib, ib, id
// 	just sets up the return stack with expected stuff and runs RESTOREINPUT.
defcode	SETINPUT, "set-input"
	pop4	x0, x1, x2, x3

	savevar	SOURCEID, x3
	savevar	TOIN, x2
	savevar	NUMIB, x1
	savevar	IB, x0
	next

// ( caddr u -- ) Save the current input state, then set the input state to the FCS on the stack.
// 	Interpret all the input, then restore the previous input state.
defword EVALUATE, "evaluate"
	fw	SAVEINPUT

	fw	LIT, 0		// ( caddr u -- caddr u 0 )
	fw	LIT, -1		// ( caddr u -- caddr u 0 -1 )
	fw	SETINPUT	// ( caddr u -- )

	fw	INTERPRETLINE

	fw	RESTOREINPUT
	fw	EXIT

defword	STARDOCOL, "*docol"
	fw	LIT, _DOCOL
	fw	EXIT

defword STARVRESET, "*vreset"
	fw	LIT, avRESET
	fw	EXIT

// ( xt -- ? ) Execute the xt on top of stack. Note that this does not end with "next" like other words - we want the "next"
//   in the called xt to return to execute's caller.
defcode	EXECUTE, "execute"
	pop	x0
	ldr	x1, [x0]
	br	x1

defword WARMSTART, "*warmstart"
	fw	REPL
	fw	EXIT

defword COLDSTART, "*coldstart"
cold_start:
	fw	LIT, WARMSTART
	fw	STARVRESET, STORE
	fw	RUNRC
	fw	REPL
	fw	EXIT

defcode	EMIT, "emit"
	pop	x0
	call	uart_putc
	next

defcode CR, "cr"
	call	cr_impl
	next

cr_impl:
	mov	x0, #10
	call	uart_putb
	mov	x0, #13
	call	uart_putb
	ret

// ( caddr u -- )
defcode	TELL, "tell"
	pop2	scx3, scx4

1:	cmp	scx4, xzr
	ble	2f

	ldrb	w0, [scx3], #1
	call	uart_putc
	sub	scx4, scx4, #1
	b	1b

2:	next

defcode	KEY, "key"
	call	uart_getc
	push	x0
	next

// ( addr len -- )
defcode TYPE, "type"
	pop2	scx3, scx4

1:	cmp	scx4, xzr
	ble	2f

	ldrb	w0, [scx3], #1
	call	uart_putb
	sub	scx4, scx4, #1
	b	1b

2:	next

// ( -- flag ) Read the next "line" from the input. Flag is true if data was written to the input buffer.
defcode	REFILL, "refill"
	loadvar	x0, SOURCEID
	cmp	x0, xzr
	bne	.ref_notuser

	ldr	x0, =default_input_buffer
	ldr	x1, =default_input_buffer_len
	loadvar	x2, STATE
	mov	x3, #1
	sub	x2, x3, x2
	call	kernel_readline

	savevar	NUMIB, x0
	savevar	TOIN, xzr
	mvn	x0, xzr
	push	x0
	b	.ref_done

.ref_notuser:
	push	xzr

.ref_done:
	next

defcode	GETTICKS, "get-ticks"
	call	timer_get_ticks
	push	x0
	next

// This is the implementation of NEXT, implemented as a macro with optional wrapper so we can indirectly
// "assemble" it into other words without having to keep it in sync in more than one place.
.macro	next_impl, wrapper:vararg=
	\wrapper ldr	x0, [fip], #8
	\wrapper ldr	x1, [x0]
	\wrapper br	x1
.endm

.macro compile_insn, insn:vararg
	fw	LIT
	\insn
.align 3
	fw	COMMA
.endm

defcode SCSLR1, "(get-scslr1)"
	mrs	x0, sctlr_el1
	push	x0
	next

defcode DHGI, "(draw-hgi)"	// ( fgrgb bgrgb addr hc pitch -- fgrgb bgrgb addr' )
	pop	x4
	pop4	x0, x1, x2, x3

	add	x5, x2, x4, LSL #3

1:	cmp	x2, x5
	beq	2f

	tst	x3, #1
	csel	x7, x0, x1, ne
	tst	x3, #2
	csel	x8, x0, x1, ne
	orr	x7, x7, x8, LSL #32
	str	x7, [x2,  #0]

	tst	x3, #4
	csel	x7, x0, x1, ne
	tst	x3, #8
	csel	x8, x0, x1, ne
	orr	x7, x7, x8, LSL #32
	str	x7, [x2, #8]

	tst	x3, #16
	csel	x7, x0, x1, ne
	tst	x3, #32
	csel	x8, x0, x1, ne
	orr	x7, x7, x8, LSL #32
	str	x7, [x2, #16]

	tst	x3, #64
	csel	x7, x0, x1, ne
	tst	x3, #128
	csel	x8, x0, x1, ne
	orr	x7, x7, x8, LSL #32
	str	x7, [x2, #24]

	add	x2, x2, x4
	lsr	x3, x3, #8
	b	1b

2:	push3	x0, x1, x2
	next

defcode DHGISCALED, "(draw-hgi-scaled)"	// ( fgrgb bgrgb addr hc pitch -- fgrgb bgrgb addr' )
	pop	x4
	pop4	x0, x1, x2, x3

	orr	x10, x0, x0, LSL #32
	orr	x11, x1, x1, LSL #32

	add	x5, x2, x4, LSL #4
	mov	x12, x2
	add	x12, x12, x4

1:	cmp	x2, x5
	beq	2f

	tst	x3, #1
	csel	x7, x10, x11, ne
	str	x7, [x2,  #0]
	str	x7, [x12, #0]

	tst	x3, #2
	csel	x7, x10, x11, ne
	str	x7, [x2,  #8]
	str	x7, [x12, #8]

	tst	x3, #4
	csel	x7, x10, x11, ne
	str	x7, [x2,  #16]
	str	x7, [x12, #16]

	tst	x3, #8
	csel	x7, x10, x11, ne
	str	x7, [x2,  #24]
	str	x7, [x12, #24]

	tst	x3, #16
	csel	x7, x10, x11, ne
	str	x7, [x2,  #32]
	str	x7, [x12, #32]

	tst	x3, #32
	csel	x7, x10, x11, ne
	str	x7, [x2,  #40]
	str	x7, [x12, #40]

	tst	x3, #64
	csel	x7, x10, x11, ne
	str	x7, [x2,  #48]
	str	x7, [x12, #48]

	tst	x3, #128
	csel	x7, x10, x11, ne
	str	x7, [x2,  #56]
	str	x7, [x12, #56]

	add	x2, x2, x4, LSL #1
	add	x12, x12, x4, LSL #1
	lsr	x3, x3, #8
	b	1b

2:	push3	x0, x1, x2
	next

// ** DODOES support **

// A create...does> word is basically a special create...;code
// word, where the forth words follow $dodoes. $dodoes thus
// adjusts FIP to point right past $dodoes and does next.
//
// You can think of this as a special DOCOL that sets FIP to a
// certain offset into the create...does> word's DFA. The offset
// corresponds to the words following the instructions emitted
// by $dodoes. Those instructions do an absolute branch to
// to _DODOES, hence the words to execute are at LR + 8.
//
// - Just like DOCOL, we enter with CFA in x0.
// - Just like DOCOL, we need to push (old) FIP for exit to pop.
// - The fith words expect DFA (i.e. CFA + 8) on stack.
_DODOES:
	pushrsp fip
	mov fip, lr
	add fip, fip, #8
	add x0, x0, #8
	push x0
	next

dodoes_body:
	ldr	scx0, . + 8
	blr	scx0
	fw	_DODOES
	.equ	dodoes_body_size, . - dodoes_body

// $dodoes ( -- addr u )  Pushes the string containing the machine code to be emitted by does> into the modified word
defword ASMDODOES, "$dodoes"
	fw	LIT, dodoes_body
	fw	LIT, dodoes_body_size
	fw	EXIT

	.purgem compile_insn

// $next ( -- addr u ) Pushes the string containing the machine code that implements NEXT, used for ;CODE defs
// code or ;code defined words.
defword ASMNEXT, "$next"
	fw	LIT, _NEXT
	fw	LIT, next_impl_size
	fw	EXIT

// ( addr len -- ) clean the dcache from addr to addr + len. Necessary around does> and code - end-code, any machine code generating words.
defcode	DCACHECLEAN, "dcache-clean"
	pop2	x0, x1
	call	cleanInvalidateDCacheRange
	next

// ( -- ) Flush and invalidate the icache
defcode ICACHEINV, "icache-flush"
	ic	iallu
	next

// ( -- ) Flush and invalidate the icache
defcode DATAMEMFENCE, "data-mem-fence"
	dmb	sy
	next

// ( -- ) Flush and invalidate the icache
defcode DATASYNCFENCE, "data-sync-fence"
	dmb	sy
	next

// ( len -- addr u )
defcode	GETCPAGE, "get-coherent-pg"
	pop	x0
	call	getCoherentPage
	push	x0
	next

defcode REBOOT, "reboot"
	call	rebootSystem
	next

// ( arg0 .. argn n scnum -- rv )
defcode SYSCALL, "*syscall"
	pop2	x11, x10
	cmp	x11, #8
	blt	1f
	mov	x11, #8

	// Load nargs registers in c ABI order - indexing backwards from 0, so that 1 arg = x0 popped ... 8 args = x7 - x0
1: 	ldr	x12, =2f
	sub	x12, x12, x11, LSL #2		// Index insns backwards according to the number of args we need to load in regs.
	br	x12

	pop	x7
	pop	x6
	pop	x5
	pop	x4
	pop	x3
	pop	x2
	pop	x1
	pop	x0
2:	nop	// regs loaded, make the call

	adrp	x12, syscall_table
	add	x12, x12, :lo12:syscall_table
	add	x12, x12, x10, LSL #3			// Index to right call
	ldr	x12, [x12]
	callreg	x12
	push	x0

	next

//
defword RC, "*rc"
	fw	LIT, _binary_src_fith_rc_5_start
	fw	LIT, _binary_src_fith_rc_5_size
	fw	EXIT

// Invoke the compiled-in RC, setting the default dict flag to F_BUILTIN so that anything in the
// RC is automatically case insensitive
defword RUNRC, "runrc"
	fw	LIT, F_BUILTIN
	fw	DEFFLAG, STORE
	fw	RC
	fw	EVALUATE
	fw	LIT, 0
	fw	DEFFLAG, STORE
	fw	EXIT

defcode ABORT, "abort"
	b 	fith_abort
	next

test_msg:	.string "This is a printf_ test: %s %ld %c\nShould read: Test 123456 c\n"
noword_msg:	.ascii "Unknown word <"
	        .equ	noword_msg_len, . - noword_msg

defvar	EORO, "*eoro"

.data
.align 4
reset_vector:	.quad	0

.align 4
.data

// **** End of read-only dictionary section ****

// Technically, everything above (except variables) can be in ROM since it is all static Fith dictionary words.
defword	VRESET, "vreset"
avRESET:
	fw	COLDSTART
	fw	EXIT

// Built in variables
defvar ASMVERS, "builtin-version", FITH_VERSION

defvar	VERBOSE, "verbose-match", 0

// STATE - 0 if immediate execution mode, 1 if compilation mode
defvar	STATE, "state"

// CP - Points to the next free byte of "compilation" memory
defvar CP, "cp"

// S0 - Stores the address of the top of the data (parameter) stack.
defvar S0, "s0"

// S0 - Stores the address of the top of the data (parameter) stack.
defvar R0, "r0"

// SP - Stores the initial address of the SP register
defvar SP, "sp"

// BASE - the current numerical base for converting literals
defvar BASE, "base", 10

defvar	DEFFLAG, "default-flag", 0

// Vector for things we want to be easily replaceable in the RC.
defvar FINDWORDVEC, "find-word-vec", FINDWORDCURRENT

defvar CURRENT, "current", var_THEWL
defvar THEWL, "thewl", name_THEWL

.data
data_segment:
.align 15

// Data sections, should be temp until we get proper allocation in place etc.
.align 5
data_stack:
	.space	DEFAULT_DSTACK_SIZE
	.equ data_stack_top, .

return_stack:
	.space	DEFAULT_RSTACK_SIZE
	.equ return_stack_top, .

// *** Cold start and fundamentals
.text
.align 3
.global fith_boot
.global fith_abort
fith_boot:
	savevar	CP, x0

	mov	x0, sp
	savevar	SP, x0

fith_abort:
	ldr	dsp, =data_stack_top
	savevar	S0, dsp

	ldr	rsp, =return_stack_top
	savevar	R0, rsp

	loadvar	x0, SP
	mov	sp, x0

reset:
	savevar	STATE, xzr

	savevar	TOIN, xzr
	savevar	SOURCEID, xzr
	savevar	NUMIB, xzr

	ldr	x0, =default_input_buffer
	savevar	IB, x0

	mov	x0, #10
	savevar	BASE, x0

	ldr	fip, =avRESET
	next				// Next will start the interpreter with cold_start as the first word

	// Default variables just push the address of their data field onto the stack
_DOVAR:
	add	x1, x0, #8
	push	x1
_VARNEXT:
	next_impl

// DOCOL is called at the start of every Fith word.
// ) CFA of a Fith word in x0
// ) Save old fip on return stack
// ) Make fip point to the 1st code word in the word we're running
// ) Start interpreting with next
_DOCOL:
	pushrsp	fip
	add fip, x0, #8

	// fall through into next

_NEXT:
	next_impl
.align 3
	.equ next_impl_size, .
