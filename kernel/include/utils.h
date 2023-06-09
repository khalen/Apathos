#pragma once

// Declare all the functions in utils.S
extern "C" {
	unsigned int get32(unsigned long addr);
	void put32(unsigned long addr, unsigned int val);
	void delay(unsigned long cycles);
	unsigned int get_el();
}
