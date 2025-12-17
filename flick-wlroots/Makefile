# Simple Makefile for Flick compositor
# For development/testing - use meson for full build

CC = gcc

# Detect wlroots package name (0.18+ uses wlroots-0.18, 0.17 uses wlroots)
WLROOTS_PKG := $(shell pkg-config --exists wlroots-0.18 && echo wlroots-0.18 || echo wlroots)

CFLAGS = -Wall -Wextra -std=c11 -g -DWLR_USE_UNSTABLE
CFLAGS += $(shell pkg-config --cflags $(WLROOTS_PKG) wayland-server xkbcommon pixman-1)
CFLAGS += -I$(BUILDDIR)/protocols -Isrc
LDFLAGS = $(shell pkg-config --libs $(WLROOTS_PKG) wayland-server xkbcommon pixman-1) -lm

WAYLAND_SCANNER = wayland-scanner
WAYLAND_PROTOCOLS_DIR = $(shell pkg-config --variable=pkgdatadir wayland-protocols)

SRCDIR = src
BUILDDIR = build

# Source files organized by component
COMPOSITOR_SRCS = $(SRCDIR)/compositor/server.c \
                  $(SRCDIR)/compositor/output.c \
                  $(SRCDIR)/compositor/input.c \
                  $(SRCDIR)/compositor/view.c

SHELL_SRCS = $(SRCDIR)/shell/gesture.c \
             $(SRCDIR)/shell/shell.c \
             $(SRCDIR)/shell/apps.c

SOURCES = $(SRCDIR)/main.c \
          $(COMPOSITOR_SRCS) \
          $(SHELL_SRCS)

# Object files (flatten into build/)
OBJECTS = $(BUILDDIR)/main.o \
          $(BUILDDIR)/server.o \
          $(BUILDDIR)/output.o \
          $(BUILDDIR)/input.o \
          $(BUILDDIR)/view.o \
          $(BUILDDIR)/gesture.o \
          $(BUILDDIR)/shell.o \
          $(BUILDDIR)/apps.o

TARGET = $(BUILDDIR)/flick

# Protocol headers to generate
PROTOCOL_HEADERS = $(BUILDDIR)/protocols/xdg-shell-protocol.h

.PHONY: all clean protocols

all: $(BUILDDIR) protocols $(TARGET)

$(BUILDDIR):
	mkdir -p $(BUILDDIR)
	mkdir -p $(BUILDDIR)/protocols

protocols: $(PROTOCOL_HEADERS)

$(BUILDDIR)/protocols/xdg-shell-protocol.h: $(WAYLAND_PROTOCOLS_DIR)/stable/xdg-shell/xdg-shell.xml
	mkdir -p $(BUILDDIR)/protocols
	$(WAYLAND_SCANNER) server-header $< $@

$(TARGET): $(OBJECTS)
	$(CC) $(OBJECTS) -o $@ $(LDFLAGS)

# Compile rules for each component
$(BUILDDIR)/main.o: $(SRCDIR)/main.c
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILDDIR)/server.o: $(SRCDIR)/compositor/server.c
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILDDIR)/output.o: $(SRCDIR)/compositor/output.c
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILDDIR)/input.o: $(SRCDIR)/compositor/input.c
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILDDIR)/view.o: $(SRCDIR)/compositor/view.c
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILDDIR)/gesture.o: $(SRCDIR)/shell/gesture.c
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILDDIR)/shell.o: $(SRCDIR)/shell/shell.c
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILDDIR)/apps.o: $(SRCDIR)/shell/apps.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -rf $(BUILDDIR)

run: all
	WLR_BACKENDS=wayland $(TARGET)

run-verbose: all
	WLR_BACKENDS=wayland $(TARGET) -v

run-headless: all
	WLR_BACKENDS=headless $(TARGET) -v
