.PHONY: build clean install test lint format run release

BINARY = aerospace-invader
INSTALL_PATH = /usr/local/bin
BUILD_DIR = .build/release

build:
	swift build

release:
	swift build -c release

clean:
	swift package clean
	rm -rf .build

install: release
	cp $(BUILD_DIR)/$(BINARY) $(INSTALL_PATH)/$(BINARY)

uninstall:
	rm -f $(INSTALL_PATH)/$(BINARY)

test:
	swift test

lint:
	swiftlint Sources Tests

format:
	swift-format -i -r Sources Tests

run: build
	swift run $(BINARY) daemon
