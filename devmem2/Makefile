# Makefile for devmem2 - Enhanced Memory Access Tool for DSMIL
# Original by Jan-Derk Bakker, Enhanced for DSMIL System

CC = gcc
CFLAGS = -Wall -Wextra -O2 -std=c99
LDFLAGS = 
TARGET = devmem2
SRC = devmem2.c

# Installation paths
PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin

.PHONY: all clean install uninstall

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $(TARGET) $(SRC) $(LDFLAGS)

clean:
	rm -f $(TARGET)

install: $(TARGET)
	install -d $(BINDIR)
	install -m 755 $(TARGET) $(BINDIR)/$(TARGET)

uninstall:
	rm -f $(BINDIR)/$(TARGET)

# Test build (no install)
test: $(TARGET)
	@echo "Build successful: $(TARGET)"
	@./$(TARGET) --help || true
