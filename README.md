# atoll-indicator

Show visual indicators in the Mac notch from the command line, via
[Atoll](https://github.com/Ebullioscopic/Atoll).

https://github.com/user-attachments/assets/a2277079-378d-4d4c-9976-0afca284bab5

Anything that can run a shell command - a hotkey (Karabiner, skhd,
BetterTouchTool), a script, a cron job, another app - can trigger an indicator:

- **flash**: an icon pops up next to the notch and disappears after a moment
  (like the compact low-battery indicator)
- **set / clear**: an icon stays next to the notch until you clear it - for
  state like "mic muted", "recording", "VPN off", "build broken"

```sh
# transient: yellow bell for 1.5s
atoll-indicator flash --icon bell.fill --color yellow

# transient, with text in Atoll's HUD below the notch
atoll-indicator flash --icon arrow.down.circle.fill --color blue \
    --title "Download finished" --hud --duration 3

# persistent state indicator
atoll-indicator set --id mic-muted --icon mic.slash.fill --color red
atoll-indicator clear --id mic-muted

# inspect
atoll-indicator list
atoll-indicator status
```

Icons are [SF Symbols](https://developer.apple.com/sf-symbols/) names. Colors
are names (`red`, `green`, ...), hex (`#ff5500`), or `accent`.

## Requirements

- macOS 13+
- [Atoll](https://github.com/Ebullioscopic/Atoll) 2.2+ running, with
  **Settings > Extensions > Enable third-party extensions** turned on
- Xcode command line tools (to build)

## Install

With Homebrew:

```sh
brew install bitmap4/tap/atoll-indicator
atoll-indicator install-agent
```

Or with the install script (installs to `~/.local/bin` and sets up the agent):

```sh
curl https://bitmap4.github.io/atoll-indicator/install.sh | sh
```

Or from source:

```sh
git clone https://github.com/bitmap4/atoll-indicator.git
cd atoll-indicator
make install
atoll-indicator install-agent
```

`~/.local/bin` must be on your `PATH` (the Homebrew build installs to the
usual brew prefix instead).

### The launchd agent

`atoll-indicator install-agent` registers a launchd login item
(`~/Library/LaunchAgents/com.github.bitmap4.atoll-indicator.plist`) that keeps
the background agent running: it starts at login and is relaunched if it ever
exits. The agent is what holds the connection to Atoll; without it, `flash`,
`set`, and the other commands report the agent as unreachable.

- `atoll-indicator status` checks that the agent is up
- `atoll-indicator uninstall-agent` stops it and removes the login item
- agent logs go to `~/Library/Logs/atoll-indicator.log`
- to run it in the foreground instead (for debugging), skip `install-agent`
  and run `atoll-indicator agent`

## How it works

A small resident agent (`atoll-indicator agent`, managed by launchd) holds a
connection to Atoll's extension RPC server (JSON-RPC over a local WebSocket,
port 9020) and waits for commands. The `atoll-indicator` CLI hands commands to
the agent over distributed notifications and exits. No polling anywhere: the
agent sits idle until you trigger it.

Indicators are rendered by Atoll as extension live activities. You can manage
the authorization under Atoll > Settings > Extensions (the app registers as
`com.github.bitmap4.atoll-indicator`). If Atoll restarts, the agent
re-authorizes and re-presents persistent indicators automatically.

> Why not AtollExtensionKit's XPC transport? Atoll registers its XPC mach
> service with the `com.apple.security.mach-services` entitlement, which
> current macOS releases don't honor for dynamic registration - the service
> name never appears in the launchd session, so XPC clients can't reach it.
> The WebSocket RPC server exposes the same API and works everywhere.

## Examples

Ready-to-use scripts in [`examples/`](examples/):

- [`mic-toggle`](examples/mic-toggle): mute/unmute the system mic with a
  persistent indicator while muted (see below)
- [`notify-done`](examples/notify-done): wrap any command and flash green or
  red when it finishes, e.g. `notify-done make build`
- [`caffeinate-toggle`](examples/caffeinate-toggle): toggle sleep prevention
  with a coffee cup pinned in the notch while active

### Mute your mic with the F5 dictation key

[`examples/mic-toggle`](examples/mic-toggle) toggles the system input volume
between 0 and its previous level, shows a persistent red `mic.slash.fill`
indicator while muted, and flashes a green mic when unmuted. Copy it to
`~/.local/bin/mic-toggle`, then bind F5 to it with
[Karabiner-Elements](https://karabiner-elements.pqrs.org/):

```json
{
    "description": "F5 (dictation/mic key) toggles microphone mute",
    "manipulators": [
        {
            "type": "basic",
            "from": { "key_code": "f5", "modifiers": { "optional": ["any"] } },
            "to": [{ "shell_command": "$HOME/.local/bin/mic-toggle" }]
        }
    ]
}
```

Tip: if you use Atoll's built-in mic privacy indicator (the orange mic shown
whenever an app listens), disable it under Atoll settings - it takes the same
slot and hides extension indicators while active.

## CLI reference

| Command | Description |
|---|---|
| `flash --icon <sf-symbol> [--color c] [--title t] [--subtitle s] [--duration secs] [--hud]` | Transient icon next to the notch (default 1.5s) |
| `set --id <id> --icon <sf-symbol> [--color c] [--title t] [--subtitle s] [--hud]` | Persistent icon until cleared |
| `clear --id <id>` | Remove a persistent indicator |
| `list` | List active persistent indicators |
| `status` | Check the agent is reachable |
| `agent` | Run the agent in the foreground |
| `install-agent` / `uninstall-agent` | Manage the launchd login item |

`--hud` additionally shows the title/subtitle as text in Atoll's sneak-peek
HUD below the notch; without it the indicator is icon-only.

## License

MIT
