BUILD_DIR    = build
SRC_DIR      = src
FIRMWARE_DIR = ../firmware
BOOT_MNT     = /Volumes/BOOTFS
CIRCLEHOME   = ../circle

INCLUDE      += -Iinclude -I$(CIRCLEHOME)/addon

all : kernel8.img

%.o : %.5
	@mkdir -p $(@D)
	$(PREFIX64)objcopy -I binary -O aarch64-unknown-elf $< $@

C_FILES     = $(wildcard $(SRC_DIR)/*.c)
C_FILES    += $(wildcard $(SRC_DIR)/*/*.c)

CPP_FILES    = $(wildcard $(SRC_DIR)/*.cpp)
CPP_FILES   += $(wildcard $(SRC_DIR)/*/*.cpp)

F_FILES     = $(wildcard $(SRC_DIR)/*.5)
F_FILES    += $(wildcard $(SRC_DIR)/*/*.5)

ASM_FILES   = $(wildcard $(SRC_DIR)/*.S)
ASM_FILES  += $(wildcard $(SRC_DIR)/*/*.S)

OBJ_FILES   = $(ASM_FILES:%.S=%.o)
OBJ_FILES  += $(C_FILES:%.c=%.o)
OBJ_FILES  += $(CPP_FILES:%.cpp=%.o)
OBJ_FILES  += $(F_FILES:%.5=%.o)

DEPLOY_FILES  = $(wildcard $(FIRMWARE_DIR)/*.*)
OVERLAY_FILES = $(wildcard $(FIRMWARE_DIR)/overlays/*.*)

OBJS = $(OBJ_FILES)
LIBS = $(CIRCLEHOME)/lib/libcircle.a $(CIRCLEHOME)/lib/usb/libusb.a $(CIRCLEHOME)/addon/fatfs/libfatfs.a \
		$(CIRCLEHOME)/addon/SDCard/libsdcard.a $(CIRCLEHOME)/lib/input/libinput.a $(CIRCLEHOME)/lib/fs/libfs.a

kernel8.img : kernel8-rpi4.img
	@echo "Obj files: $(OBJ_FILES)"
	@echo "Building Apathos kernel.."
	@echo ""
	@cp $< $@

install : kernel8.img
	@cp kernel8.img $(IMG_DIR)

include $(CIRCLEHOME)/Rules.mk
