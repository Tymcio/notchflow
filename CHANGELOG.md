# Changelog

All notable changes to NotchFlow are documented here. Version numbers follow [Semantic Versioning](https://semver.org/).

## [1.0] - 2026-07-12

### Added

- Notch island with hover-to-expand on built-in and external displays
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
