# NotchFlow

Native macOS notch utility for Apple Silicon MacBooks. Transparent, lightweight, privacy-first.

[![CI](https://github.com/Tymcio/notchflow/actions/workflows/ci.yml/badge.svg)](https://github.com/Tymcio/notchflow/actions/workflows/ci.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

**[Download](https://github.com/Tymcio/notchflow/releases/latest)** · **[Website](https://notchflow.eu)** · **[Free vs Premium](docs/free-vs-premium.md)** · **[Contributing](CONTRIBUTING.md)**

<p align="center">
  <img src="website/assets/screenshots/01-music.png" alt="NotchFlow — music player in the notch island" width="900"/>
</p>

<p align="center"><em>Hover the top of your screen — the island expands into music, calendar, shelf, timers, notes, clipboard, and mirror.</em></p>

---

## What is NotchFlow?

NotchFlow turns the MacBook notch into a useful, non-intrusive island — a floating `NSPanel` around the physical notch on the built-in display. With an external monitor attached, the island follows your cursor; on screens without a hardware notch it uses a centered capsule at the top. **Requires a notched MacBook** — does not run on Macs without a notch (Mac mini, iMac, Mac Studio, etc.).

- Menu bar app (no Dock icon) — look for the capsule icon after launch
- Hover the **top-center of your screen** to expand the island
- Built with SwiftUI + AppKit, distributed as a signed & notarized DMG with Sparkle updates

## Features

| Area | Free | Premium |
|------|------|---------|
| **Island** | Default size, system theme | Custom width, clipboard height, Midnight / Aurora / Ember themes |
| **Media** | Spotify & Apple Music controls, artwork, scrubber | + Lyrics snippet |
| **Shelf** | 1 item (drop on island) | Up to 12 items, multi-file ZIP staging |
| **Notes** | 5 quick notes | Unlimited + pin |
| **Clipboard** | 5 entries (opt-in monitoring) | 50 entries + search |
| **Mirror** | Tab visible (locked) | Live camera preview |
| **Calendar** | Month grid + upcoming preview | — |
| **HUD** | Custom volume & brightness overlays | — |
| **Integrations** | URL scheme, local API (media) | Local API (notes, clipboard, mirror) |
| **Hide mode** | — | Hide island for selected apps (settings panel) |

Full breakdown: **[docs/free-vs-premium.md](docs/free-vs-premium.md)**

## Screenshots

| Music | Calendar | Shelf |
|:---:|:---:|:---:|
| ![Music player](website/assets/screenshots/01-music.png) | ![Calendar](website/assets/screenshots/02-calendar.png) | ![Shelf](website/assets/screenshots/03-shelf.png) |

| Timer | Stopwatch | Pomodoro |
|:---:|:---:|:---:|
| ![Timer](website/assets/screenshots/04-timer.png) | ![Stopwatch](website/assets/screenshots/05-stopwatch.png) | ![Pomodoro](website/assets/screenshots/06-pomodoro.png) |

| Notes | Clipboard | Mirror |
|:---:|:---:|:---:|
| ![Notes](website/assets/screenshots/07-notes.png) | ![Clipboard](website/assets/screenshots/08-clipboard.png) | ![Mirror](website/assets/screenshots/09-camera.png) |

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon (ARM64)
- Xcode 15+ / Swift 5.9+

## Download

Official builds (signed, notarized, with premium activation):

- **[Latest release](https://github.com/Tymcio/notchflow/releases/latest)** — drag `NotchFlow.app` to Applications
- **[notchflow.eu](https://notchflow.eu)** — purchase premium license

Verify the signature:

```bash
spctl -a -vv /Applications/NotchFlow.app
codesign -dv --verbose=4 /Applications/NotchFlow.app
```

## Build from source

```bash
git clone https://github.com/Tymcio/notchflow.git
cd notchflow
swift build -c release
Scripts/package_app.sh   # bundles Sparkle.framework — required
open build/NotchFlow.app
```

> **Important:** Do not run the raw binary from `.build/` — it will crash without `Sparkle.framework`. Always use `Scripts/package_app.sh` or `Scripts/compile_and_run.sh`.

See [docs/polar-setup.md](docs/polar-setup.md) for checkout and license configuration.

Self-built copies run all free features. Premium features require a license from [notchflow.eu](https://notchflow.eu).

## Development

```bash
swift test
Scripts/compile_and_run.sh
```

Performance budget (idle): ~0% CPU, < 50 MB RAM. See [docs/performance.md](docs/performance.md).

## Integrations

- **Raycast** — local HTTP API + extension in [`integrations/raycast/`](integrations/raycast/notchflow/)
- **URL scheme** — `notchflow://play-pause`, `show-island`, `add-note?text=…`, `mirror-toggle`

Setup guide: [docs/raycast-integration.md](docs/raycast-integration.md)

## Security & privacy

- No telemetry in v1.0
- Clipboard monitoring is **opt-in** and stored locally
- Local API binds to `127.0.0.1` only; token in Keychain
- Network use limited to license validation (Polar) and Sparkle updates
- No Terminal install scripts — drag-to-Applications only

Details: [website/privacy.html](website/privacy.html) · [website/security.html](website/security.html)

## Project structure

```
Sources/NotchFlow/     App, features, licensing, views
Tests/                 Swift Testing suite
Scripts/               Build, package, release tooling
docs/                  Performance, integrations, public-repo guide
integrations/raycast/  Raycast extension (MIT)
website/               Static marketing site (notchflow.eu)
```

## License

Source code is available under **[GPL-3.0](LICENSE)**. You may build and run NotchFlow from source for personal use.

Official signed builds and premium feature activation require a license from [notchflow.eu](https://notchflow.eu). The Raycast extension is [MIT](integrations/raycast/notchflow/package.json).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). When publishing updates, follow [docs/public-repository.md](docs/public-repository.md).
