#pragma once

// D1.10.2 in Aarch64-A ref manual
#define SYNC_INVALID_EL1T           0
#define IRQ_INVALID_EL1T            1
#define FIQ_INVALID_EL1T            2
#define ERROR_INVALID_EL1T          3

#define SYNC_INVALID_EL1H           4
#define IRQ_INVALID_EL1H            5
#define FIQ_INVALID_EL1H            6
#define ERROR_INVALID_EL1H          7

#define SYNC_INVALID_EL0_64         8
#define IRQ_INVALID_EL0_64          9
#define FIQ_INVALID_EL0_64          10
#define ERROR_INVALID_EL0_64        11

#define SYNC_INVALID_EL0_32         12
#define IRQ_INVALID_EL0_32          13
#define FIQ_INVALID_EL0_32          14
#define ERROR_INVALID_EL0_32        15

#define STACK_FRAME_SIZE			256
