<p align="center"><img src="Resources/icon.png" width="128" alt="AI Usage Meter icon"></p>

# AI Usage Meter

A tiny macOS menu bar app with a floating widget that shows how much of your
**Codex** and **Claude Code** rate limits you have left, with countdowns to the
5-hour and weekly resets.

## Requirements

- macOS 14 or later
- Xcode Command Line Tools (`xcode-select --install`)
- [Codex CLI](https://github.com/openai/codex) signed in, for the Codex section
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) signed in with a Claude Pro/Max account (`claude` then `/login`), for the Claude section

## Download

Grab `AI-Usage-Meter-macOS.zip` from the [latest release](https://github.com/Solaimanx/ai-usage-meter/releases/latest),
unzip it and drag **AI Usage Meter** into Applications. The app isn't notarised, so the
first time, right-click it and choose **Open** (or run
`xattr -dr com.apple.quarantine "/Applications/AI Usage Meter.app"`).

## Build from source

```sh
./build.sh
open "build/AI Usage Meter.app"
```

Drag the app into `/Applications` to keep it. To start it at login, add it in
System Settings > General > Login Items.

## Features

- Floating, draggable widget that stays on top across all Spaces
- Remaining percentage and reset countdown for the 5-hour and weekly windows
- Settings menu: show Codex, Claude Code, or both
- Widget colour themes: Classic (black), Light, Midnight blue, Forest, Sunset
- Menu bar icon with manual refresh

## How it reads usage

- **Codex:** runs `codex app-server` locally and asks it for the account's rate limits.
  If `codex` isn't found automatically, set `CODEX_PATH` to its full path.
- **Claude Code:** reads the OAuth token Claude Code stores in your login Keychain
  (`Claude Code-credentials`) and calls Anthropic's usage endpoint, the same one
  Claude Code's `/usage` command uses. The first time, macOS asks to allow Keychain
  access; choose "Always Allow". The token never leaves your Mac except to Anthropic.

Usage refreshes every 5 minutes, or on demand from the menu bar.

## Licence

MIT, see [LICENSE](LICENSE).

> This uses an undocumented Anthropic endpoint, so it may change without notice.

> Not affiliated with OpenAI or Anthropic.
