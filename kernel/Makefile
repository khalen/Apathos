BUILD_DIR    = build
SRC_DIR      = src
FIRMWARE_DIR = ../firmware
BOOT_MNT     = /Volumes/BOOTFS

ARM_CC      = /usr/local/opt/llvm/bin/clang
ARM_LD      = /usr/local/opt/llvm/bin/ld.lld
ARM_OBJCOPY = /usr/local/opt/llvm/bin/llvm-objcopy
CFLAGS      = --target=aarch64-elf -mcpu=cortex-a72+nosimd -Wall -Iinclude -g -ffreestanding -nostdlib -mgeneral-regs-only -xc++ -std=c++11
AFLAGS      = --target=aarch64-elf -mcpu=cortex-a72+nosimd -Iinclude

all : kernel8.img

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

DEPLOY_FILES  = $(wildcard $(FIRMWARE_DIR)/*.*)
OVERLAY_FILES = $(wildcard $(FIRMWARE_DIR)/overlays/*.*)

DEP_FILES = $(OBJ_FILES:%.o=%.d)
-include $(DEP_FILES)

kernel8.img : $(SRC_DIR)/link.ld $(OBJ_FILES)
	@echo "Building Apathos kernel.."
	@echo ""

	$(ARM_LD) -m aarch64elf -nostdlib -T $(SRC_DIR)/link.ld -o $(BUILD_DIR)/kernel8.elf $(OBJ_FILES)
	$(ARM_OBJCOPY) $(BUILD_DIR)/kernel8.elf -O binary kernel8.img

install : kernel8.img
	@cp kernel8.img $(IMG_DIR)
