#!/bin/sh
# Installer for atoll-indicator (https://github.com/bitmap4/atoll-indicator).
# Downloads the latest release binary, or builds from source if that fails.
#
#   curl https://bitmap4.github.io/atoll-indicator/install.sh | sh
#
# Installs to ~/.local/bin by default; override with PREFIX=/some/dir.
set -eu

REPO="bitmap4/atoll-indicator"
PREFIX="${PREFIX:-$HOME/.local}"
BINDIR="$PREFIX/bin"
BIN="$BINDIR/atoll-indicator"

say() { printf '%s\n' "$*"; }

install_from_release() {
    url=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" |
        grep -o '"browser_download_url": *"[^"]*macos-universal\.tar\.gz"' |
        head -1 | sed 's/.*"\(https[^"]*\)"/\1/')
    [ -n "$url" ] || return 1

    say "Downloading $url"
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    curl -fsSL "$url" -o "$tmp/atoll-indicator.tar.gz"
    tar -xzf "$tmp/atoll-indicator.tar.gz" -C "$tmp"
    mkdir -p "$BINDIR"
    install -m 755 "$tmp/atoll-indicator" "$BIN"
}

install_from_source() {
    command -v swift >/dev/null 2>&1 || {
        say "error: no release binary available and swift is not installed."
        say "Install the Xcode command line tools (xcode-select --install) and retry."
        exit 1
    }
    say "Building from source (this needs the Xcode command line tools)..."
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    git clone --depth 1 "https://github.com/$REPO.git" "$tmp/src"
    (cd "$tmp/src" && swift build -c release)
    mkdir -p "$BINDIR"
    install -m 755 "$tmp/src/.build/release/atoll-indicator" "$BIN"
}

install_from_release || install_from_source

say "Installed $BIN"
"$BIN" install-agent

case ":$PATH:" in
    *":$BINDIR:"*) ;;
    *) say "note: $BINDIR is not on your PATH; add it to your shell profile." ;;
esac

say ""
say "Done. Make sure Atoll is running with Settings > Extensions >"
say "'Enable third-party extensions' turned on, then try:"
say "  atoll-indicator flash --icon bell.fill --color yellow"
