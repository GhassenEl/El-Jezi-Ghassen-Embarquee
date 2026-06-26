CC      ?= gcc
CFLAGS  ?= -Wall -Wextra -O2 -std=c11
TARGET  = build/gpio-blink
SRC     = src/main.c

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(SRC) | build
	$(CC) $(CFLAGS) -o $@ $<

build:
	mkdir -p build

clean:
	rm -rf build
