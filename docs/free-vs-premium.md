# Free vs Premium

NotchFlow is **open source** (GPL-3.0) — you can build and run it yourself with full free-tier features. Official signed builds from [notchflow.eu](https://notchflow.eu) add convenient distribution, Sparkle updates, and premium activation.

## Pricing

| Plan | Price | Notes |
|------|-------|-------|
| **Free** | €0 | Self-build or official build, free-tier limits |
| **Premium Annual** | €12/year | All premium features, 2 Macs |
| **Premium Lifetime** | €24 one-time | All premium features, perpetual |
| **Agents addon** | €14.90 one-time | AI coding agents in the notch, 2 Macs |

Purchase: [notchflow.eu](https://notchflow.eu) (checkout via [Polar](https://polar.sh))

## Feature comparison

### Island & appearance

| Feature | Free | Premium |
|---------|------|---------|
| Hover-to-expand island | ✓ | ✓ |
| Multi-display support (notched MacBook) | ✓ | ✓ |
| Default size (400×188) | ✓ | ✓ |
| Custom width (280–420) | — | ✓ |
| Custom clipboard height (168–480) | — | ✓ |
| Dynamic height (calendar, media, shelf, …) | ✓ | ✓ |
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
| Agents (coding) | — | See Agents addon |

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

### Notifications

| Feature | Free | Premium |
|---------|------|---------|
| App notifications in notch | — | ✓ |
| Hide message body (privacy) | — | ✓ |
| Close system banner when shown in island | — | ✓ |

### System & integrations

| Feature | Free | Premium | Agents addon |
|---------|------|---------|--------------|
| Volume / brightness HUD | ✓ | ✓ | — |
| Launch at login | ✓ | ✓ | — |
| URL scheme (`notchflow://`) | ✓ | ✓ | — |
| Local API — media & island | ✓ | ✓ | — |
| Local API — notes, clipboard, mirror | — | ✓ | — |
| Local API — agent events | — | — | ✓ |
| Hide island for selected apps | — | ✓ | — |
| Hide island settings panel | — | ✓ | — |
| Sparkle auto-updates | Official builds | Official builds | — |

### Agents addon (€14.90 one-time)

Separate Polar product — not included in Premium. Unlock with a `NOTCHFLOW_AGENTS_…` key (or any Polar key whose product/metadata is Agents).

| Feature | Without addon | With Agents |
|---------|---------------|-------------|
| Agents island tab | Locked | ✓ |
| Idle live activity for agent sessions | — | ✓ |
| Allow / Deny permission prompts in the notch | — | ✓ |
| Claude Code hooks (auto-install) | — | ✓ |
| Codex, Cursor, OpenCode, Gemini CLI, Kimi, DeepSeek | — | ✓ (via hooks / Local API) |
| Jump to terminal / IDE | — | ✓ (app activation) |

## Planned features (roadmap)

Upcoming releases **v1.1 → v1.3** are documented in **[docs/roadmap.md](roadmap.md)**. Summary of **planned** tier assignment for new work (not yet shipped):

### v1.1 — Looks better (all free)

| Feature | Free | Premium |
|---------|------|---------|
| Album art colors (gradient from artwork) | ✓ | ✓ |
| Spring animations (+ reduce motion) | ✓ | ✓ |
| HUD redesign + keyboard backlight HUD | ✓ | ✓ |
| Auto-hide island in fullscreen | ✓ | ✓ |
| Screen capture privacy (hidden in screenshots/recordings) | ✓ | ✓ |

### v1.2 — Trust and reach

| Feature | Free | Premium |
|---------|------|---------|
| Localization (en, pl, de, it, es) | ✓ | ✓ | *Shipped v1.0.15+* |
| Energy budget / performance transparency | ✓ | ✓ |
| Battery / charging idle live activity | ✓ | ✓ |
| License enforcement + trial (stable) | Free tier unchanged | Premium as today |

### v1.3 — Convenience

| Feature | Free | Premium |
|---------|------|---------|
| AirDrop from shelf | — | ✓ |
| Bluetooth connect/disconnect + battery | ✓ | ✓ |
| Caffeine (prevent sleep) toggle | ✓ | ✓ |
| Audio output switch in media view | ✓ | ✓ |

See [roadmap.md](roadmap.md) for scope, non-goals, and competitor rationale.

## Implementation reference

Limits are defined in `Sources/NotchFlow/Core/NotchFlowConstants.swift`:

```swift
static let freeNotesLimit = 5
static let freeClipboardLimit = 5
static let premiumClipboardLimit = 50
```

Premium status is determined by `LicenseStatus.isPremium` (annual or lifetime tier from Polar license validation). Agents addon is `LicenseStatus.hasAgentsAddon` (separate Polar product / key).

## Self-build vs official build

| | Self-build (GitHub) | Official build (notchflow.eu) |
|--|---------------------|-------------------------------|
| Free features | ✓ | ✓ |
| Premium features | Requires license key | Requires license key |
| Agents addon | Requires Agents key | Requires Agents key |
| Code signing | Your machine | Apple Developer ID |
| Notarization | No | Yes |
| Sparkle updates | Disabled (no ed key) | Enabled |
| Gatekeeper trust | Manual | Automatic |

## Updating this document

When changing tier limits or adding gated features:

1. Update this file
2. Update `README.md` feature table
3. Update `docs/roadmap.md` if a planned item ships or scope changes
4. Update `website/index.html` pricing section
5. Update `docs/raycast-integration.md` if API tiers change
6. Run `Scripts/publish-to-github.sh` to sync the public repo
