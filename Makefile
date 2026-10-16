# Default to ~/.local (no sudo). A quoted "~" never expands, so expand it here.
PREFIX ?= $(HOME)/.local
BINDIR := $(patsubst ~%,$(HOME)%,$(PREFIX))/bin
VERSION := $(shell sed -n 's/^let version = "\(.*\)"/\1/p' Sources/aix/main.swift)
DIST := .build/dist/aix-$(VERSION)-arm64-macos.tar.gz

.PHONY: build test install uninstall dist clean

build:
	swift build -c release --disable-sandbox

test:
	swift test

install: build
	install -d "$(BINDIR)"
	install -m 755 .build/release/aix "$(BINDIR)/aix"

uninstall:
	rm -f "$(BINDIR)/aix"

# Release tarball for GitHub Releases / a Homebrew formula. Sign and notarize before
# publishing a direct download (see README → Distributing).
dist: build
	mkdir -p .build/dist
	tar -czf $(DIST) -C .build/release aix
	shasum -a 256 $(DIST)

clean:
	swift package clean
	rm -rf .build/dist
