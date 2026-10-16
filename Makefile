PREFIX ?= /usr/local
VERSION := $(shell sed -n 's/^let version = "\(.*\)"/\1/p' Sources/aix/main.swift)
DIST := .build/dist/aix-$(VERSION)-arm64-macos.tar.gz

.PHONY: build test install uninstall dist clean

build:
	swift build -c release --disable-sandbox

test:
	swift test

install: build
	install -d "$(PREFIX)/bin"
	install -m 755 .build/release/aix "$(PREFIX)/bin/aix"

uninstall:
	rm -f "$(PREFIX)/bin/aix"

# Release tarball for GitHub Releases / a Homebrew formula. Sign and notarize before
# publishing a direct download (see README → Distributing).
dist: build
	mkdir -p .build/dist
	tar -czf $(DIST) -C .build/release aix
	shasum -a 256 $(DIST)

clean:
	swift package clean
	rm -rf .build/dist
