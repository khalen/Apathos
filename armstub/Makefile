SRC_DIR      = src
IMG_DIR     := ../images
PREFIX64 ?= /usr/local/bin/aarch64-elf-

all : armstub8.img install

clean :
	@rm -rf *.o *.img

armstub8.img: $(SRC_DIR)/armstub8.S
	$(PREFIX64)gcc -DGIC=1 -o armstub8.o -c $(SRC_DIR)/armstub8.S
	$(PREFIX64)ld --section-start=.text=0 -o armstub8.elf armstub8.o
	$(PREFIX64)objdump -D armstub8.elf > armstub8.lst
	$(PREFIX64)objcopy armstub8.elf -O binary armstub8.img

install : armstub8.img
	@mkdir -p $(IMG_DIR)
	@cp armstub8.img $(IMG_DIR)

