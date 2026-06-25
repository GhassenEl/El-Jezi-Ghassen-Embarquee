obj-m += eljezi_gpio.o

KDIR ?= /lib/modules/$(shell uname -r)/build
PWD  := $(shell pwd)

.PHONY: all clean install unload

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean

install:
	sudo insmod eljezi_gpio.ko
	@echo "Device : /dev/eljezi_gpio"

unload:
	sudo rmmod eljezi_gpio || true
