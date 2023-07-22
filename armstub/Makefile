BUILD_DIR    = build
SRC_DIR      = src
IMG_DIR     := ../images

ARM_CC      = /usr/local/opt/llvm/bin/clang
ARM_LD      = /usr/local/opt/llvm/bin/ld.lld
ARM_OBJCOPY = /usr/local/opt/llvm/bin/llvm-objcopy
AFLAGS      = --target=aarch64-elf -mcpu=cortex-a72 -DGCI=1 -Iinclude

all : armstub8.img install

clean :
	@rm -rf $(BUILD_DIR) *.img

$(BUILD_DIR)/%_s.o : $(SRC_DIR)/%.S
	@mkdir -p $(@D)
	$(ARM_CC) $(AFLAGS) -c $< -o $@

ASM_FILES = $(wildcard $(SRC_DIR)/*.S)
OBJ_FILES = $(ASM_FILES:$(SRC_DIR)/%.S=$(BUILD_DIR)/%_s.o)

armstub8.img : $(OBJ_FILES)
	$(ARM_LD) -m aarch64elf -nostdlib --section-start=.text=0 -o $(BUILD_DIR)/armstub8.elf $(BUILD_DIR)/armstub8_s.o
	$(ARM_OBJCOPY) $(BUILD_DIR)/armstub8.elf -O binary armstub8.img

install : armstub8.img
	@mkdir -p $(IMG_DIR)
	@cp armstub8.img $(IMG_DIR)
