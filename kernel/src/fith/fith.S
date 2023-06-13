// This is Fith, an arm64 Forth variant. It is intended to have the minimum amount of primitive words to be
// reasonably fast, while remaining small enough to reason about. Inspired by Jonesforth, an amazing 32 bit I86
// literate Forth written in assembly. We use a different dictionary format for and a couple of tricks for
// something reasonably approaching efficiency,

	.set FITH_VERSION, 42

// Reserved registers. These have been allocated from the "callee saved" registers, which makes
// interoperating with the C kernel easier. This should be less meaningful over time, as the eventual
// goal is for even the lowest level functionality to be written in Fith itself.

// Important system registers
dsp	.req	x19	// Fith data stack
rsp	.req	x20	// Fith return stack
fip	.req	x21	// Fith Instruction Pointer

// Scratch registers
sc0	.req	x23
sc1	.req	x24
sc2	.req	x25
sc3	.req	x26
sc4	.req	x27
sc5	.req	x28

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

// Copy dsp to sp, ensuring 128 byte alignment as per abi
.macro	round_dsp_to_sp
	mov	sc0, dsp
	tst	sc0, #0F
	beq	1f
	sub	sc0, sc0, #8
1:	mov	sp, sc0
.endm

// This is the implementation of NEXT, implemented as a macro with optional wrapper so we can indirectly
// "assemble" it into other words without having to keep it in sync in more than one place.
.macro	next_impl, wrapper:vararg=
	\wrapper ldr	x0, [fip], #8
	\wrapper ldr	x0, [x0]
	\wrapper br	x0
.endm

.macro	next
	b	_NEXT
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
// 1: [1b| Len flags, 7b| Name0] -> 1 byte length + flags, 1st 7 chars of name
// 2: [8b| Name1]		 -> Next 8 chars of name
// 3: [8b| Codeword]		 -> Addr of DOCOL (below) or a jump to the immediately following insn

	.set	dict_link, 0	// Dict terminator

.macro create_name label, qname, qname2, flags
.section .rodata
.align 3
.global	name_\label

name_\label:
	.quad	dict_link
	.set	dict_link, name_\label		// Link to previous word and update address
	.byte	\flags | (str_end_\label - str_\label)
str_\label:
	.ascii	"\qname"
	.align 3
	.ascii	"\qname2"
str_end_\label:
	.align 3
.global \label
\label:
	// Code word will follow
.endm

#define fw	.quad

// Define a new word in "Fith" - subsequent words should be .quad of the CFAs of the words called by this word, ie. the
// result of normal Fith compilation
.macro	defword	label, qname, qname2="", flags=F_BUILTIN
	create_name	\label, "\qname", "\qname2", \flags
	// Fith execution codeword
	.quad	_DOCOL
.endm

// Define a new word in assembly - the CFA in this case just the address of the first asm insn in the word
// continue.
.macro	defcode	label, qname, qname2="", flags=F_BUILTIN
	create_name	\label, "\qname", "\qname2", \flags
	// Asm execution codeword
	.quad	code_\label
.text
.global	code_\label
code_\label:
.endm

// Define a new variable
.macro defvar label, qname, initial=0, qname2="", flags=F_BUILTIN
	defcode \label, "\qname", "\qname2", \flags
	ldr	x0, =var_\label
	push	x0
	next
.data
.align 3
.global var_\label
var_\label:
	.quad	\initial
.endm

// Define a new constant
.macro defconst label, qname, value, qname2="", flags=F_BUILTIN
	defcode \label, "\qname", "\qname2", \flags
	ldr	x0, =\value
	push	x0
	next
.endm

// Built in variables
// STATE - 0 if immediate execution mode, 1 if compilation mode
defvar	STATE, "state",,,
// HERE - Points to the next free byte of memory available for compilation
defvar HERE, "here"
// LATEST - Points to the most recently defined dictionary entry (head of the dict linked list)
defvar LATEST,"latest", name_EXECUTE	// EXECUTE must be the last word defined to properly link to user definitionss
// S0 - Stores the address of the top of the data (parameter) stack.
defvar S0, "s0"
// BASE - the current numerical base for converting literals
defvar BASE, "base", 10


// *** Cold start and fundamentals
.text
.align 3
.global fith_start
fith_start:
	ldr	x0, =var_S0
	mov	dsp, sp
	str	x1, [x0]	// Orig stack position in S0
	ldr	rsp, =return_stack_top
	ldr	x0, =data_segment	// Initial rtn stack and DS
	ldr	x1, =var_HERE		// HERE starts out pointing at the initial data seg
	str	x0, [x1]
	ldr	fip, =cold_start
	next				// Next will start the interpreter with cold_start as the first word

// DOCOL is called at the start of every Fith word.
// ) CFA of a Fith word in x0
// ) Save old fip on return stack
// ) Make fip point to the 1st code word in the word we're running
// ) Start interpreting with next
_DOCOL:
	pushrsp	fip
	add fip, x0, 8

	// fall through into next

_NEXT:
	next_impl

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
	pop3	x0, x2, x1
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

defcode	FROMR, "r>"	// (a --r: a)
	poprsp	x0
	push	x0
	next

defcode TWOTOR, "2>r"	// (a b --r: a b)
	pop2	x1, x0
	pushrsp	x1
	pushrsp	x0
	next

defcode TWOFROMR, "2r>" // (r: a b -- a b)
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

defcode	RDROP, "rdrop"	// (r: a --)
	poprsp	x0
	next

defcode TWORDROP, "2rdrop"
	poprsp	x0
	poprsp	x0
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

defcode	LSHIFT, "lshift"	// (a b -- a << b)
	pop2	x1, x0
	lsl	x0, x1, x0
	push	x0
	next

defcode	MUL, "*"	// (a b -- a * b)
	pop2	x1, x0
	mul	x2, x1, x0
	push	x2
	next

// This is unsigned division - not sure if the default / should be signed or unsigned
defcode DIV, "/"
	pop2	x1, x0
	udiv	x2, x1, x0
	push	x2
	next

// Arm doesn't have that nice /mod insn like Intel, so we do it the old fashioned way: n mod m = n - (n / m * m)
defcode	MOD, "mod"
	pop2	x1, x0		// (a b --) x1 = a x0 = b
	udiv	x2, x1, x0	// x2 = a / b
	mul	x0, x2, x0	// x0 = (a / b) * b
	sub	x0, x1, x0	// x0 = (a - (a / b * b))
	push	x0
	next

defword	DIVMOD, "/mod"	// (a b -- a/b a%b)
	fw	TWODUP	// (a b -- a b a b)
	fw	DIV	// (a b a b -- a b a/b)
	fw	ROT	// (a b a/b -- a/b a b)
	fw	MOD	// (a/b a b -- a/b a%b)
	fw	EXIT

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

// (t p q -- flag)	Test if t is within p and q, that is, p <= t < q.
// This is a little more complicated than it seems, because the standard says that:
// a) It has to work for signed AND unsigned numbers (but not testing signed vs. unsigned or vice versa, they all must be the same type)
// b) They have to work consistently when the comparison range straddles the wrapping boundary of the max cell size.
// The standard impl is:
// : WITHIN ( test low high -- flag ) OVER - >R - R> U< ;
defcode	WITHIN, "within"
	pop3	x0, x1, x2		// x0 = test, x1 = low, x2 = high
	sub	x3, x2, x1		// x3 = high - low
	sub	x4, x0, x1		// x4 = test - low
	cmp	x3, x4			// x3 < x4?
	csetm	x0, lo			// lo = cc flag clear, unsigned <
	push	x0
	next

// *** Branching
defcode BRANCH, "branch"
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
defcode	STORE, "!"	// (addr v --) *addr = v
	pop2	x1, x0
	str	x0, [x1]
	next

defcode CSTORE, "c!"	// (addr v --) *(byte *)addr = v & 0xFF
	pop2	x1, x0
	strb	w0, [x1]
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

// This is essentially memcpy. It relies on the ASSUMPTION that on arm64 w/no unaligned address exceptions, a larger unaligned load or store
// is still faster than n byte fetches or stores. Based on from guthub.com/ClickHouse/ClickHouse/memcpy.h; DOES NOT HANDLE OVERLAPPING SRC
// AND DST CORRECTLY
defcode	MOVE, "move"	// (srcaddr dstaddr u --)	Move u address units from srcaddr to dstaddr.
#ifndef OPTIMIZED_MOVE
	pop3	x0, x1, x2

1:	cmp	x2, #0
	beq	done

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
	bhi	med_size

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
	b	done

wordsize:
	cmp	x2, #4
	blo	halfwordsize

	// Copy last 4 bytes
	sub	x2, x2, 4
	ldr	w8, [x0, x2]
	str	w8, [x1, x2]
	// 1st 4 bytes
	ldr	w9, [x0]
	str	w9, [x1]
	b	done

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
	b	done

bytesize:
	cmp	x2, #1
	blo	done
	ldrb	w8, [x0]
	strb	w8, [x1]
	b	done

	// Large enough to loop, not large enough to care too much about dst alignment
med_size:
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
	b	done

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
	b	abort

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

done:
	next

// Uses move, as implemented in the Forth 20xx standard
defcode	CMOVE, "cmove"	// (fromaddr toaddr u --)	for i in 0 .. u	toaddr[i] = fromaddr[i]
