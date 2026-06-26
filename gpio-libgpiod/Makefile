CC      ?= gcc
CFLAGS  ?= -Wall -Wextra -O2 -std=c11
LDFLAGS ?= -lgpiod
TARGET  = build/gpio-blink
SRC     = src/gpio_blink.c

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(SRC) | build
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

build:
	mkdir -p build

clean:
	rm -rf build

install-deps:
	@echo "Sur Raspberry Pi OS : sudo apt install -y libgpiod-dev gpiod"
