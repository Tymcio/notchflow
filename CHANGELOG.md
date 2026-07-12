# Changelog

All notable changes to NotchFlow are documented here. Version numbers follow [Semantic Versioning](https://semver.org/).

## [1.0.1] - 2026-07-12

### Added

- Live Activities in idle notch (incoming/active calls, app notifications, focus timer, media wings)
- Upcoming calendar events preview in the Calendar tab
- App blacklist settings panel (hide island for selected apps, Premium)
- Lyrics snippet display in the media player (Premium, opt-in via Privacy settings)
- Terms of service, privacy policy, and GDPR-compliant analytics on the website

### Changed

- Website redesign with refreshed screenshots and hero
- Settings window uses NavigationSplitView
- Clipboard search is Premium-only (free tier shows locked state)
- Hover-to-expand waits 220 ms so quick clicks in the menu bar reach apps below
- Shelf drag-out restored on file icons without breaking open-on-click

### Fixed

- Shelf file opening after pinning temporary copies (bookmarks no longer point at deleted files)
- Menu bar icon and hover detection
- Screenshot display artifacts on the marketing site

## [1.0.0] - 2026-07-06

### Added

- Notch island with hover-to-expand on built-in and external displays
- Media controls for Spotify and Apple Music (play/pause, seek, artwork, idle wings)
- Floating shelf with APFS hard-link storage
- Quick notes (5 free / unlimited premium)
- Clipboard history with opt-in monitoring (5 free / 50 premium)
- Custom volume and brightness HUD overlays
- Calendar month grid tab
- Camera mirror tab (premium)
- Premium licensing via LemonSqueezy (annual & lifetime)
- Sparkle auto-updates on official signed builds
- Local HTTP API and Raycast extension
- URL scheme deeplinks (`notchflow://`)
- GPL-3.0 public source release

[1.0.1]: https://github.com/Tymcio/notchflow/releases/tag/v1.0.1
[1.0.0]: https://github.com/Tymcio/notchflow/releases/tag/v1.0.0
