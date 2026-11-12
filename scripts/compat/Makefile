CC ?= gcc
CFLAGS ?= -O2 -Wall -Wextra -fPIC
LDFLAGS ?= -shared -ldl -Wl,-s

TARGET = libdroidspaces-compat.so
PREFIX ?= /usr/local
LIBDIR ?= $(PREFIX)/lib

all: $(TARGET)

$(TARGET): libdroidspaces-compat.c
	$(CC) $(CFLAGS) $< $(LDFLAGS) -o $@

install: $(TARGET)
	install -d -m 0755 $(DESTDIR)$(LIBDIR)
	install -m 0755 $(TARGET) $(DESTDIR)$(LIBDIR)/$(TARGET)
	if [ -z "$(DESTDIR)" ]; then \
		grep -qxF "$(LIBDIR)/$(TARGET)" /etc/ld.so.preload 2>/dev/null || \
			echo "$(LIBDIR)/$(TARGET)" >> /etc/ld.so.preload; \
	fi

clean:
	rm -f $(TARGET)

.PHONY: all install clean
