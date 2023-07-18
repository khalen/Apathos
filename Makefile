export FIRMWARE_DIR	:= firmware
export IMG_DIR  := $(CURDIR)/images
export BIN_DIR	:= $(CURDIR)/bin

ALL_DIRS		:= $(wildcard */.)
DEPLOY_KERNEL	:= chainload
STUB_IMG		:= armstub

BOOT_MNT := /Volumes/BOOTFS
BOOT_C    = $(wildcard $(BOOT_MNT))

.PHONY: all default clean deploy install $(ALL_DIRS)

all clean install default : $(ALL_DIRS)

$(ALL_DIRS) :
	@if [ -e $@/Makefile ] ; then \
		echo "### Running make $(MAKECMDGOALS) in $@..." ; \
		$(MAKE) -C $@ $(MAKECMDGOALS) ; \
	fi

clean :
	@rm -rf $(IMG_DIR)/*
	@rm $(BIN_DIR)/conman

DEPLOY_FILES  = $(wildcard $(FIRMWARE_DIR)/*.*) $(DEPLOY_KERNEL)/config.txt $(IMG_DIR)/armstub8.img
KERNEL_IMG	  = $(IMG_DIR)/$(DEPLOY_KERNEL)8.img
OVERLAY_FILES = $(wildcard $(FIRMWARE_DIR)/overlays/*.*)

deploy : $(KERNEL_IMG) $(DEPLOY_KERNEL) $(DEPLOY_FILES) $(OVERLAY_FILES)
ifeq (,$(BOOT_C))
	@echo "Boot device not present at $(BOOT_MNT), not deploying."
else
	@echo "### Deploying images and firmware files to $(BOOT_MNT)..."
	@echo ""

	@echo "Kernel..."
	@cp $(KERNEL_IMG) $(BOOT_MNT)/kernel8.img

	@echo "$(DEPLOY_FILES)..."
	@cp $(DEPLOY_FILES) $(BOOT_MNT)

	@mkdir -p $(BOOT_MNT)/overlays
	@echo "$(OVERLAY_FILES)..."
	@cp $(OVERLAY_FILES) $(BOOT_MNT)/overlays
	@sync

	@echo "### Unmounting $(BOOT_MNT)..."
	diskutil unmount $(BOOT_MNT)
endif
