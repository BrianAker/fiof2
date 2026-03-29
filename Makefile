PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
INSTALL ?= install

SHELL := /bin/sh

PROGRAMS := file2dir files2dir
ZSH_PROGRAMS := $(PROGRAMS)
PERL_PROGRAMS := folders2dir nibble
ZSH_SOURCES := $(addprefix src/,$(addsuffix .zsh,$(ZSH_PROGRAMS)))
PERL_SOURCES := $(addprefix src/,$(addsuffix .pl,$(PERL_PROGRAMS)))
SOURCES := $(ZSH_SOURCES) $(PERL_SOURCES)
BUILT := $(addsuffix .zsh,$(ZSH_PROGRAMS)) $(addsuffix .pl,$(PERL_PROGRAMS))
TESTS := t/folders2dir.t t/nibble.t

.PHONY: all build check test install uninstall clean distclean

all: build

build: $(BUILT)

check: $(SOURCES) $(BUILT)
	zsh -n $(ZSH_SOURCES)
	zsh -n $(addsuffix .zsh,$(ZSH_PROGRAMS))
	perl -c $(PERL_SOURCES)
	perl -c $(addsuffix .pl,$(PERL_PROGRAMS))
	prove $(TESTS)

test: check

install: build
	$(INSTALL) -d "$(DESTDIR)$(BINDIR)"
	$(INSTALL) -m 0755 file2dir.zsh "$(DESTDIR)$(BINDIR)/file2dir"
	$(INSTALL) -m 0755 files2dir.zsh "$(DESTDIR)$(BINDIR)/files2dir"
	$(INSTALL) -m 0755 folders2dir.pl "$(DESTDIR)$(BINDIR)/folders2dir"
	$(INSTALL) -m 0755 nibble.pl "$(DESTDIR)$(BINDIR)/nibble"

uninstall:
	rm -f "$(DESTDIR)$(BINDIR)/file2dir" "$(DESTDIR)$(BINDIR)/files2dir" "$(DESTDIR)$(BINDIR)/folders2dir" "$(DESTDIR)$(BINDIR)/nibble"

clean:
	rm -f $(BUILT)

distclean: clean

file2dir.zsh: src/file2dir.zsh
	cp "$<" "$@"
	chmod 0755 "$@"

files2dir.zsh: src/files2dir.zsh
	cp "$<" "$@"
	chmod 0755 "$@"

folders2dir.pl: src/folders2dir.pl
	cp "$<" "$@"
	chmod 0755 "$@"

nibble.pl: src/nibble.pl
	cp "$<" "$@"
	chmod 0755 "$@"
