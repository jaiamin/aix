PREFIX ?= $(HOME)/.local
BINDIR := $(patsubst ~%,$(HOME)%,$(PREFIX))/bin
VERSION := $(shell sed -n 's/^let version = "\(.*\)"/\1/p' Sources/aix/main.swift)

build:
	swift build -c release

test:
	swift test

install: build
	install -d "$(BINDIR)"
	install -m 755 .build/release/aix "$(BINDIR)/aix"

uninstall:
	rm -f "$(BINDIR)/aix"

# Release tarball for the Homebrew formula (github.com/jaiamin/homebrew-aix).
dist: build
	mkdir -p .build/dist
	tar -czf .build/dist/aix-$(VERSION)-arm64-macos.tar.gz -C .build/release aix
	shasum -a 256 .build/dist/aix-$(VERSION)-arm64-macos.tar.gz

.PHONY: build test install uninstall dist
