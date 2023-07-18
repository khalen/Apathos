#pragma once

#include "base_defs.h"

#ifdef __cplusplus
extern "C"
{
#endif

void handle_timer_1(void);
void handle_timer_3(void);
void timer_init();
u64 timer_get_ticks();
u64 timer_get_millis();
void timer_sleep_ticks(u64 sleep_ticks);
void timer_sleep_ms(u64 sleep_ms);


typedef void (*timer_callback)(u64 curTicks);

#ifdef __cplusplus
}
#endif
