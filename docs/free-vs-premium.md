# Free vs Premium

NotchFlow is **open source** (GPL-3.0) — you can build and run it yourself with full free-tier features. Official signed builds from [notchflow.eu](https://notchflow.eu) add convenient distribution, Sparkle updates, and premium activation.

## Pricing

| Plan | Price | Notes |
|------|-------|-------|
| **Free** | €0 | Self-build or official build, free-tier limits |
| **Premium Annual** | €12/year | All premium features, 2 Macs |
| **Premium Lifetime** | €24 one-time | All premium features, perpetual |

Purchase: [notchflow.eu](https://notchflow.eu)

## Feature comparison

### Island & appearance

| Feature | Free | Premium |
|---------|------|---------|
| Hover-to-expand island | ✓ | ✓ |
| Multi-display support | ✓ | ✓ |
| Default size (400×188) | ✓ | ✓ |
| Custom width (280–420) | — | ✓ |
| Custom height (120–200) | — | ✓ |
| System theme | ✓ | ✓ |
| Midnight / Aurora / Ember themes | — | ✓ |

### Modules

| Feature | Free | Premium |
|---------|------|---------|
| Media controls (Spotify, Apple Music) | ✓ | ✓ |
| Lyrics snippet | — | ✓ |
| Calendar month grid | ✓ | ✓ |
| Upcoming events preview | ✓ | ✓ |
| Quick notes | 5 max | Unlimited + pin |
| Clipboard history | 5 max | 50 + search |
| Camera mirror | Locked | Live preview |

### Shelf

| Feature | Free | Premium |
|---------|------|---------|
| Drag-and-drop on island | ✓ | ✓ |
| Pinned shortcuts | 3 max | 20 max |
| Temporary dropped items | 1 | 12 |
| Multi-file ZIP staging | — | ✓ |

### Focus timer

| Feature | Free | Premium |
|---------|------|---------|
| Countdown timer (presets) | ✓ | ✓ |
| Stopwatch | ✓ | ✓ |
| Idle notch countdown | ✓ | ✓ |
| Pomodoro with auto-chaining | — | ✓ |

### Calls & notifications

| Feature | Free | Premium |
|---------|------|---------|
| Incoming calls in notch | — | ✓ |
| App notifications in notch | — | ✓ |
| Hide message body (privacy) | — | ✓ |

### System & integrations

| Feature | Free | Premium |
|---------|------|---------|
| Volume / brightness HUD | ✓ | ✓ |
| Launch at login | ✓ | ✓ |
| URL scheme (`notchflow://`) | ✓ | ✓ |
| Local API — media & island | ✓ | ✓ |
| Local API — notes, clipboard, mirror | — | ✓ |
| Hide island for selected apps | — | ✓ |
| Hide island settings panel | — | ✓ |
| Sparkle auto-updates | Official builds | Official builds |

## Implementation reference

Limits are defined in `Sources/NotchFlow/Core/NotchFlowConstants.swift`:

```swift
static let freeNotesLimit = 5
static let freeClipboardLimit = 5
static let premiumClipboardLimit = 50
```

Premium status is determined by `LicenseStatus.isPremium` (annual or lifetime tier from LemonSqueezy validation).

## Self-build vs official build

| | Self-build (GitHub) | Official build (notchflow.eu) |
|--|---------------------|-------------------------------|
| Free features | ✓ | ✓ |
| Premium features | Requires license key | Requires license key |
| Code signing | Your machine | Apple Developer ID |
| Notarization | No | Yes |
| Sparkle updates | Disabled (no ed key) | Enabled |
| Gatekeeper trust | Manual | Automatic |

## Updating this document

When changing tier limits or adding gated features:

1. Update this file
2. Update `README.md` feature table
3. Update `website/index.html` pricing section
4. Update `docs/raycast-integration.md` if API tiers change
5. Run `Scripts/publish-to-github.sh` to sync the public repo
