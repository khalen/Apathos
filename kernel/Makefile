BUILD_DIR    = build
SRC_DIR      = src
FIRMWARE_DIR = ../firmware
BOOT_MNT     = /Volumes/BOOTFS

ARM_CC      = /usr/local/bin/aarch64-elf-gcc
ARM_AS      = /usr/local/bin/aarch64-elf-gcc
ARM_LD      = /usr/local/bin/aarch64-elf-ld
ARM_OBJCOPY = /usr/local/bin/aarch64-elf-objcopy
CCFLAGS     = -mcpu=cortex-a72+nosimd -Wall -Iinclude -g -ffreestanding -fpermissive -nostdlib -mgeneral-regs-only -xc++ -std=c++17
CFLAGS	    = -mcpu=cortex-a72+nosimd -Wall -Iinclude -g -ffreestanding -nostdlib -mgeneral-regs-only -std=c17 
AFLAGS      = -Iinclude

all : kernel8.img

clean :
	rm -rf $(BUILD_DIR) *.img

$(BUILD_DIR)/%_c.o : $(SRC_DIR)/%.c
	@mkdir -p $(@D)
	$(ARM_CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/%_cc.o : $(SRC_DIR)/%.cc
	@mkdir -p $(@D)
	$(ARM_CC) $(CCFLAGS) -c $< -o $@

$(BUILD_DIR)/%_s.o : $(SRC_DIR)/%.S
	@mkdir -p $(@D)
	$(ARM_AS) $(AFLAGS) -c $< -o $@

$(BUILD_DIR)/%_5.o : $(SRC_DIR)/%.5
	@mkdir -p $(@D)
	$(ARM_OBJCOPY) -I binary -O aarch64-unknown-elf $< $@

CC_FILES    = $(wildcard $(SRC_DIR)/*.cc)
CC_FILES   += $(wildcard $(SRC_DIR)/*/*.cc)

F_FILES     = $(wildcard $(SRC_DIR)/*.5)
F_FILES    += $(wildcard $(SRC_DIR)/*/*.5)
ASM_FILES   = $(wildcard $(SRC_DIR)/*.S)
ASM_FILES  += $(wildcard $(SRC_DIR)/*/*.S)
OBJ_FILES   = $(ASM_FILES:$(SRC_DIR)/%.S=$(BUILD_DIR)/%_s.o)
OBJ_FILES  += $(C_FILES:$(SRC_DIR)/%.c=$(BUILD_DIR)/%_c.o)
OBJ_FILES  += $(CC_FILES:$(SRC_DIR)/%.cc=$(BUILD_DIR)/%_cc.o)
OBJ_FILES  += $(F_FILES:$(SRC_DIR)/%.5=$(BUILD_DIR)/%_5.o)

DEPLOY_FILES  = $(wildcard $(FIRMWARE_DIR)/*.*)
OVERLAY_FILES = $(wildcard $(FIRMWARE_DIR)/overlays/*.*)

DEP_FILES = $(OBJ_FILES:%.o=%.d)
-include $(DEP_FILES)

kernel8.img : $(SRC_DIR)/link.ld $(OBJ_FILES)
	@echo "Obj files: $(OBJ_FILES)"
	@echo "Building Apathos kernel.."
	@echo ""

	$(ARM_LD) -m aarch64elf --no-warn-rwx-segments -nostdlib -T $(SRC_DIR)/link.ld -o $(BUILD_DIR)/kernel8.elf $(OBJ_FILES)
	$(ARM_OBJCOPY) $(BUILD_DIR)/kernel8.elf -O binary kernel8.img

install : kernel8.img
	@cp kernel8.img $(IMG_DIR)
