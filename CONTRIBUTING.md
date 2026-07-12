# Contributing to NotchFlow

Thank you for your interest in NotchFlow! This is the **public** repository — all commits here are visible to everyone.

## Prerequisites

- macOS 14+
- Xcode 15.4+ (CI uses Xcode 15.4 on macOS 14 runners)
- Swift 5.9+
- Apple Silicon Mac (ARM64)

## Getting started

```bash
git clone https://github.com/Tymcio/notchflow.git
cd notchflow
swift build -c release
Scripts/package_app.sh
swift test
```

For iterative development:

```bash
Scripts/compile_and_run.sh
```

## Pull request workflow

1. Fork the repository
2. Create a feature branch from `main`
3. Make your changes
4. Run `swift test` and `Scripts/package_app.sh` locally
5. Open a PR against `main`

CI (`.github/workflows/ci.yml`) runs build, test, and package on every push/PR.

## Code layout

| Path | Purpose |
|------|---------|
| `Sources/NotchFlow/App/` | Entry point, app state, delegate |
| `Sources/NotchFlow/Features/` | Media, notes, clipboard, mirror, calendar |
| `Sources/NotchFlow/Licensing/` | LemonSqueezy validation, Keychain |
| `Sources/NotchFlow/Managers/` | Display, HUD, shelf, pomodoro |
| `Sources/NotchFlow/Views/` | Island UI, settings, overlays |
| `Sources/NotchFlow/Services/` | Local API, URL scheme, Sparkle |

## Premium feature gates

When adding or changing features, respect the free/premium model documented in [docs/free-vs-premium.md](docs/free-vs-premium.md):

- Gate UI with `appState.isPremium` or `settings.isPremiumEnabled`
- Enforce limits via `NotchFlowConstants` (`freeNotesLimit`, `freeClipboardLimit`, etc.)
- Update `docs/free-vs-premium.md`, `README.md`, and `website/index.html` if the tier changes
- Mark new local API endpoints with their tier in `docs/raycast-integration.md`

## Performance

Follow [docs/performance.md](docs/performance.md):

- Event-driven architecture — no polling loops for media, HUD, or license checks
- Mouse tracking via global `mouseMoved` events only
- Media monitor sleeps when playback is paused

## What not to commit

Never commit secrets or signing material. These are gitignored:

- `.env`, `secrets/`, `*.p12`, `*.mobileprovision`
- `build/`, `.build/`, `*.dmg`, `*.zip`, `*.app`
- `notary-log.json`

CI/release secrets (`DEVELOPER_ID_*`, `NOTARY_PROFILE`, `SPARKLE_*`) live in GitHub Actions settings only.

## Publishing updates (maintainers)

When releasing a new version, follow [docs/public-repository.md](docs/public-repository.md):

```bash
# 1. Bump version.env
# 2. Update CHANGELOG.md
# 3. Sync public-safe content and push
Scripts/publish-to-github.sh

# 4. Tag release (triggers signed build workflow)
git tag v1.0 && git push origin v1.0
```

## Language

UI strings are currently in **Polish**. New user-facing strings should match existing conventions until i18n is added.

## Questions

Open a [GitHub Issue](https://github.com/Tymcio/notchflow/issues) for bugs or feature requests.
