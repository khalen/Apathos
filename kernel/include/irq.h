#pragma once

extern "C"
{
void irq_init_vectors();
void irq_enable();
void irq_disable();

void enable_interrupt_controller();
void disable_interrupt_controller();
}
