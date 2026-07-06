PREFIX ?= $(HOME)/.local
BINARY := .build/release/atoll-indicator

.PHONY: build install uninstall clean

build:
	swift build -c release

install: build
	mkdir -p "$(PREFIX)/bin"
	install -m 755 "$(BINARY)" "$(PREFIX)/bin/atoll-indicator"
	@echo "Installed. Run 'atoll-indicator install-agent' to start the agent at login."

uninstall:
	-"$(PREFIX)/bin/atoll-indicator" uninstall-agent 2>/dev/null
	rm -f "$(PREFIX)/bin/atoll-indicator"

clean:
	swift package clean
