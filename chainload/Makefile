BUILD_DIR    = build
SRC_DIR      = src
CIRCLEHOME   = ../circle

C_FILES      = $(wildcard $(SRC_DIR)/*.c)
CPP_FILES    = $(wildcard $(SRC_DIR)/*.cpp)
ASM_FILES    = $(wildcard $(SRC_DIR)/*.S)
OBJ_FILES    = $(C_FILES:%.c=%.o)
OBJ_FILES   += $(CPP_FILES:%.cpp=%.o)
OBJ_FILES   += $(C_FILES:%.S=%.o)

EXTRACLEAN  += chainload8.img

INCLUDE += -Iinclude
CPP_FLAGS += -DSERIAL_GPIO_SELECT=14

OBJS	= $(OBJ_FILES)
LIBS	= $(CIRCLEHOME)/lib/libcircle.a

chainload8.img : kernel8-rpi4.img
	@cp	kernel8-rpi4.img chainload8.img

install : chainload8.img
	@echo Copying chainload8.img to $(IMG_DIR)...
	@mkdir -p $(IMG_DIR)
	@cp chainload8.img $(IMG_DIR)

include $(CIRCLEHOME)/Rules.mk

