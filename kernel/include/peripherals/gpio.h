#pragma once

#include "base_defs.h"
#include "peripherals/base.h"

template <int field_size>
static inline u32 gpio_setPinData(reg32* base, u32 pin, u32 value)
{
    const u32    field_mask = (1 << field_size) - 1;
    const u32    num_fields = 32 / field_size;
    reg32* reg              = base + (pin / num_fields);
    const u32    shift      = (pin % num_fields) * field_size;

    u32 curval = *reg;
    curval &= ~(field_mask << shift);
    curval |= value << shift;
    *reg = curval;
    return 1;
}

extern "C" {

typedef struct PACKED
{
    reg32 data[2];
    reg32 _reserved;
} GpioPinData;
static_assert(sizeof(GpioPinData) == 0x0C, "GpioPinData has unexpected size");

typedef struct PACKED
{
    reg32       FunctionSelect[6];
    reg32       _reserved0;

    GpioPinData OutputSet;
    GpioPinData OutputClr;
    GpioPinData Level;
    GpioPinData EvDetectStatus;
    GpioPinData ReDetectEnable;
    GpioPinData FeDetectEnable;
    GpioPinData HiDetectEnable;
    GpioPinData LoDetectEnable;
    GpioPinData AsyncReDetect;
    GpioPinData AsyncFeDetect;

    reg32       _reserved1[20];

    reg32       PupPdnCntrlRegs[4];
} GpioRegs;
static_assert(sizeof(GpioRegs) == 0xF4, "GpioRegs has the wrong size");

#define GPIO_REGS  ((GpioRegs *)(PERIPHERAL_BASE + 0x00200000))

enum
{
    GPIO_MAX_PIN = 53,
    GPIO_FUNCTION_ALT5 = 2,
};

enum
{
    Pull_None = 0
};

static inline u32 gpio_set(u32 pin, u32 value)
{
    return gpio_setPinData<1>(GPIO_REGS->OutputSet.data, pin, value);
}

static inline u32 gpio_clear(u32 pin, u32 value )
{
    return gpio_setPinData<1>(GPIO_REGS->OutputClr.data, pin, value);
}

static inline u32 gpio_pull(u32 pin, u32 value)
{
    return gpio_setPinData<2>(GPIO_REGS->PupPdnCntrlRegs, pin, value);
}

static inline u32 gpio_function(u32 pin, u32 value)
{
    return gpio_setPinData<3>(GPIO_REGS->FunctionSelect, pin, value);
}

static inline void gpio_useAsAlt5(u32 pin)
{
    gpio_pull(pin, Pull_None);
    gpio_function(pin, GPIO_FUNCTION_ALT5);
}

}
