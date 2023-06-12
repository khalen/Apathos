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
.macro	pushdsp	reg=x0
	str	\reg, [dsp, #-8]!
.endm

.macro	popdsp	reg=x0
	ldr	\reg, [dsp], #8
.endm

.macro	push2	reg0=x0, reg1=x1
	str	\reg0, [dsp, #-8]!
	str	\reg1, [dsp, #-8]!
.endm

.macro	pop2	reg0=x0, reg1=x1
	ldr	\reg1, [dsp], #8
	ldr	\reg0, [dsp], #8
.endm

.macro	push3	reg0=x0, reg1=x1, reg2=x2
	str	\reg0, [dsp, #-8]!
	str	\reg1, [dsp, #-8]!
	str	\reg2, [dsp, #-8]!
.endm

.macro	pop3	reg0=x0, reg1=x1, reg2=x2
	ldr	\reg2, [dsp], #8
	ldr	\reg1, [dsp], #8
	ldr	\reg0, [dsp], #8
.endm

.macro	push4	reg0=x0, reg1=x1, reg2=x2, reg3=x3
	stp	\reg0, \reg1, [dsp, #-16]!
	stp	\reg2, \reg3, [dsp, #-16]!
.endm

.macro	pop4	reg0=x0, reg1=x1, reg2=x2, reg3=x3
	ldp	\reg3, \reg2, [dsp], #16
	ldp	\reg1, \reg0, [dsp], #16
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
	\wrap_insn ldr	x0, [fip], #8
	\wrap_insn ldr	x0, [x0]
	\wrap_insn br	x0
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

.macro create_name	label, name, name2, flags
.section .rodata
.align 3
.global	name_\label

name_\label:
	.quad	dict_link
	.set	dict_link, name_\label		// Link to previous word and update address
	.byte	\flags | (str_end_\label - str_\label)
str_\label:
	.ascii	"\name"
	.align 3
	.ascii	"\name2"
str_end_\label:
	.align 3
.global \label
\label:
	// Code word will follow
.endm

// Define a new word in "Fith" - subsequent words should be .quad of the CFAs of the words called by this word, ie. the
// result of normal Fith compilation
.macro	defword	label, name, name2 = "", flags = F_BUILTIN
	create_name	label, name, name2, flags
	// Fith execution codeword
	.quad	_DOCOL
.endm

// Define a new word in assembly - the CFA in this case just the address of the first asm insn in the word
// continue.
.macro	defcode	label, name, name2 = "", flags = F_BUILTIN
	create_name	label, name, name2, flags
	// Asm execution codeword
	.quad	code_\label
.text
.global	code_\label
code_\label:
.endm

// Define a new variable
.macro defvar label, name, initial=0, name2 = "", flags = F_BUILTIN
	defcode label, name, name2, flags
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
.macro defconst label, name, value, name2 = "", flags = F_BUILTIN
	defcode label, name, name2, flags
	ldr	x0, =\value
	push	x0
	next
.endm

// Built in variables
// STATE - 0 if immediate execution mode, 1 if compilation mode
defvar	STATE, "state"
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
	lsr	x0, =data_segment	// Initial rtn stack and DS
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
	add	dsp, 8
	next

defcode DUP, "dup"
	ldr	x0, [dsp]
	push	x0
	next

defcode	OVER, "over"
	ldr	x0, [dsp, #8]
