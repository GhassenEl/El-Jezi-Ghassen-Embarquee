CC      ?= gcc
CFLAGS  ?= -Wall -Wextra -O2 -std=c11
TARGET  = build/test-eljezi-gpio

.PHONY: all clean

all: $(TARGET)

$(TARGET): test_cdev.c | build
	$(CC) $(CFLAGS) -o $@ $<

build:
	mkdir -p build

clean:
	rm -rf build
