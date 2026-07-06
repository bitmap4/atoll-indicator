APP_DIR   := $(HOME)/Applications/AtollIndicator.app
BIN_LINK  := $(HOME)/.local/bin/atoll-indicator
BINARY    := .build/release/atoll-indicator

.PHONY: build install uninstall clean

build:
	swift build -c release

# Atoll identifies XPC clients through LaunchServices, so the agent must run
# from inside an app bundle. The CLI is a symlink into the same bundle.
install: build
	mkdir -p "$(APP_DIR)/Contents/MacOS"
	cp Sources/atoll-indicator/Info.plist "$(APP_DIR)/Contents/Info.plist"
	cp "$(BINARY)" "$(APP_DIR)/Contents/MacOS/atoll-indicator"
	codesign --force --sign - "$(APP_DIR)"
	mkdir -p "$(dir $(BIN_LINK))"
	ln -sf "$(APP_DIR)/Contents/MacOS/atoll-indicator" "$(BIN_LINK)"
	@echo "Installed. Run 'atoll-indicator install-agent' to start the agent at login."

uninstall:
	-"$(BIN_LINK)" uninstall-agent 2>/dev/null
	rm -f "$(BIN_LINK)"
	rm -rf "$(APP_DIR)"

clean:
	swift package clean
