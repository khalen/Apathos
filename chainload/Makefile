BUILD_DIR    = build
SRC_DIR      = src

ARM_CC      = /usr/local/opt/llvm/bin/clang
ARM_LD      = /usr/local/opt/llvm/bin/ld.lld
ARM_OBJCOPY = /usr/local/opt/llvm/bin/llvm-objcopy
CFLAGS      = --target=aarch64-elf -mcpu=cortex-a72+nosimd -Wall -Iinclude -O2 -g -ffreestanding -nostdlib -mgeneral-regs-only -xc++ -std=c++11
AFLAGS      = --target=aarch64-elf -mcpu=cortex-a72+nosimd -Iinclude

all : chainload8.img

clean :
	rm -rf $(BUILD_DIR) *.img

$(BUILD_DIR)/%_c.o : $(SRC_DIR)/%.c
	@mkdir -p $(@D)
	$(ARM_CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/%_s.o : $(SRC_DIR)/%.S
	@mkdir -p $(@D)
	$(ARM_CC) $(AFLAGS) -c $< -o $@

C_FILES     = $(wildcard $(SRC_DIR)/*.c)
ASM_FILES   = $(wildcard $(SRC_DIR)/*.S)
OBJ_FILES   = $(C_FILES:$(SRC_DIR)/%.c=$(BUILD_DIR)/%_c.o)
OBJ_FILES  += $(ASM_FILES:$(SRC_DIR)/%.S=$(BUILD_DIR)/%_s.o)

DEP_FILES = $(OBJ_FILES:%.o=%.d)
-include $(DEP_FILES)

chainload8.img : $(SRC_DIR)/link.ld $(OBJ_FILES)
	$(ARM_LD) -m aarch64elf -nostdlib -T $(SRC_DIR)/link.ld -o $(BUILD_DIR)/chainload8.elf $(OBJ_FILES)
	$(ARM_OBJCOPY) $(BUILD_DIR)/chainload8.elf -O binary chainload8.img

install : chainload8.img
	@echo Copying chainload8.img to $(IMG_DIR)...
	@mkdir -p $(IMG_DIR)
	@cp chainload8.img $(IMG_DIR)
