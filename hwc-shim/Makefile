# Flick HWComposer Shim - Makefile
#
# Build with: make
# Install with: make install PREFIX=/usr
#
# Dependencies:
#   - libhybris-hwcomposerwindow
#   - libhwc2
#   - libgralloc

CC ?= gcc
AR ?= ar
PKG_CONFIG ?= pkg-config

PREFIX ?= /usr/local
LIBDIR ?= $(PREFIX)/lib
INCLUDEDIR ?= $(PREFIX)/include

# Compiler flags
CFLAGS ?= -O2 -g
CFLAGS += -Wall -Wextra -Werror
CFLAGS += -fPIC
CFLAGS += -I$(CURDIR)/include

# Get flags from pkg-config (may not be available on all systems)
HYBRIS_CFLAGS := $(shell $(PKG_CONFIG) --cflags libhybris-hwcomposerwindow 2>/dev/null || echo "-I/usr/include/hybris/hwcomposerwindow")
HYBRIS_LIBS := $(shell $(PKG_CONFIG) --libs libhybris-hwcomposerwindow 2>/dev/null || echo "-lhybris-hwcomposerwindow")

HWC2_CFLAGS := $(shell $(PKG_CONFIG) --cflags libhwc2 2>/dev/null || echo "-I/usr/include/hybris/hwc2")
HWC2_LIBS := $(shell $(PKG_CONFIG) --libs libhwc2 2>/dev/null || echo "-lhwc2")

GRALLOC_LIBS := -lgralloc

CFLAGS += $(HYBRIS_CFLAGS) $(HWC2_CFLAGS)
LDFLAGS += $(HYBRIS_LIBS) $(HWC2_LIBS) $(GRALLOC_LIBS)

# Source files
SRCS = src/flick_hwc.c
OBJS = $(SRCS:.c=.o)

# Output
LIB_STATIC = libflick_hwc.a
LIB_SHARED = libflick_hwc.so.1
LIB_SONAME = libflick_hwc.so.1
LIB_LINK = libflick_hwc.so

.PHONY: all clean install uninstall

all: $(LIB_STATIC) $(LIB_SHARED)

$(LIB_STATIC): $(OBJS)
	$(AR) rcs $@ $^

$(LIB_SHARED): $(OBJS)
	$(CC) -shared -Wl,-soname,$(LIB_SONAME) -o $@ $^ $(LDFLAGS)

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

clean:
	rm -f $(OBJS) $(LIB_STATIC) $(LIB_SHARED)

install: all
	install -d $(DESTDIR)$(LIBDIR)
	install -d $(DESTDIR)$(INCLUDEDIR)
	install -m 644 $(LIB_STATIC) $(DESTDIR)$(LIBDIR)/
	install -m 755 $(LIB_SHARED) $(DESTDIR)$(LIBDIR)/
	ln -sf $(LIB_SHARED) $(DESTDIR)$(LIBDIR)/$(LIB_LINK)
	install -m 644 include/flick_hwc.h $(DESTDIR)$(INCLUDEDIR)/

uninstall:
	rm -f $(DESTDIR)$(LIBDIR)/$(LIB_STATIC)
	rm -f $(DESTDIR)$(LIBDIR)/$(LIB_SHARED)
	rm -f $(DESTDIR)$(LIBDIR)/$(LIB_LINK)
	rm -f $(DESTDIR)$(INCLUDEDIR)/flick_hwc.h
