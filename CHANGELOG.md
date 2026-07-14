# Changelog

All notable changes to NotchFlow are documented here. Version numbers follow [Semantic Versioning](https://semver.org/).

## [1.0.16] - 2026-07-14

### Fixed

- CI: correct `ClipboardEntry` argument order in `ShelfManagerTests` so `swift test` compiles on GitHub Actions

## [1.0.15] - 2026-07-14

### Added

- Localization: English source UI with Polish, German, Italian, and Spanish translations (String Catalog + `loc()` helper)
- Language picker in Settings → General (per-app override via `AppleLanguages`, relaunch on change)
- App brand icons in notification settings when apps are not installed; fixed Rambox bundle ID (`com.rambox`)
- `generate_localizations.py` script and localization completeness test

### Changed

- Settings detail panes use grouped form layout with section footers (cleaner spacing and hierarchy)
- Settings window reliably comes to the foreground when opened from the menu bar
- Media idle state label localized (“Not Playing” → e.g. “Brak odtwarzania” in Polish)
- Call/notification banner keyword detection extended for de/it/es system languages

## [1.0.14] - 2026-07-14

### Changed

- Website: redesigned feature mockups (music, calendar, shelf), trust pills, hero badge, and “Works in the background” visual
- Website: Google Analytics 4 (`G-2G5766758K`) with GDPR Consent Mode v2 — loads only after consent
- Website: event tracking (downloads, checkout, CTA, outbound links, screenshot tabs, scroll depth, theme toggle)
- Website: `site_language` (`en`/`pl`) on all analytics events for EN/PL reporting in GA4

## [1.0.13] - 2026-07-14

### Changed

- Settings: version and “Check for updates” moved to the left sidebar footer
- Settings window comes to the foreground when opened (including from full-screen apps)

## [1.0.12] - 2026-07-14

### Changed

- Require a notched MacBook at launch; show an alert and exit on unsupported Macs
- Clarify website FAQ and docs: external displays supported only with a notched MacBook host

## [1.0] - 2026-07-12

### Added

- Notch island with hover-to-expand on the built-in notched display; follows the cursor on external displays when attached to a notched MacBook
- Media controls for Spotify and Apple Music (play/pause, seek, artwork, idle wings)
- Live Activities in idle notch (incoming/active calls, app notifications, focus timer, media wings)
- Floating shelf with APFS hard-link storage and drag-and-drop on the island
- Quick notes (5 free / unlimited premium)
- Clipboard history with opt-in monitoring (5 free / 50 premium)
- Calendar month grid with upcoming events preview and open-in-Calendar actions
- Custom volume and brightness HUD overlays
- Camera mirror tab (premium)
- App blacklist settings panel (hide island for selected apps, premium)
- Lyrics snippet display in the media player (premium, opt-in via Privacy settings)
- Premium licensing via Polar (annual & lifetime)
- Sparkle auto-updates on official signed builds
- Local HTTP API and Raycast extension
- URL scheme deeplinks (`notchflow://`)
- Terms of service, privacy policy, and GDPR-compliant analytics on the website
- GPL-3.0 public source release

### Changed

- Website redesign with refreshed screenshots and hero
- Settings window uses NavigationSplitView
- Clipboard search is premium-only (free tier shows locked state)
- Hover-to-expand waits 220 ms so quick clicks in the menu bar reach apps below
- Island height adapts dynamically to tab content; premium height slider applies to clipboard only
- Premium payments and license keys via Polar (Merchant of Record)
- Shelf drag-out restored on file icons without breaking open-on-click

### Fixed

- Calendar layout clipping with multiple day events and dynamic panel height
- False file-drop chrome when switching tabs (stale drag pasteboard, `onDrop` targeting)
- Shelf file opening after pinning temporary copies (bookmarks no longer point at deleted files)
- Menu bar icon and hover detection
- Screenshot display artifacts on the marketing site

[1.0]: https://github.com/Tymcio/notchflow/releases/tag/v1.0
