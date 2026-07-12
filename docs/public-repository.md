# Public repository guide

This repository (`https://github.com/Tymcio/notchflow`) is **public**. Everything pushed here is visible to the world. Use this guide when updating NotchFlow to keep the public repo accurate and safe.

## What belongs in the public repo

| Include | Path / item |
|---------|-------------|
| Application source | `Sources/`, `Tests/` |
| Build & dev scripts | `Scripts/package_app.sh`, `compile_and_run.sh`, `profile_idle.sh` |
| Release scripts (no secrets inside) | `Scripts/sign-and-notarize.sh`, `make_appcast.sh` |
| Package manifest | `Package.swift`, `Package.resolved`, `version.env` |
| Entitlements | `NotchFlow.entitlements` |
| Documentation | `README.md`, `CONTRIBUTING.md`, `CHANGELOG.md`, `docs/` |
| Integrations | `integrations/raycast/` |
| Marketing site source | `website/` |
| CI workflows | `.github/workflows/ci.yml`, `release.yml` |
| License | `LICENSE` |

## What must NEVER be pushed

| Exclude | Reason |
|---------|--------|
| `.env` with API keys | Secrets |
| `secrets/` directory | Signing credentials |
| `*.p12`, `*.mobileprovision` | Certificates |
| `build/`, `.build/` | Build artifacts |
| `*.dmg`, `*.zip`, `*.app` | Binaries (use GitHub Releases) |
| `notary-log.json` | May contain internal IDs |
| `SPARKLE_PRIVATE_ED_KEY` value | Signing key — GitHub secret only |
| `DEVELOPER_ID_*` values | Signing identity — GitHub secret only |

All of the above are listed in `.gitignore`. Run the publish script before pushing to verify.

## Release checklist

Use this every time you update the plugin:

### 1. Version bump

Edit `version.env`:

```bash
MARKETING_VERSION=1.0
BUILD_NUMBER=1
```

### 2. Changelog

Add an entry to `CHANGELOG.md` under the new version.

### 3. Free / premium docs

If features or limits changed:

- [ ] `docs/free-vs-premium.md`
- [ ] `README.md` feature table
- [ ] `website/index.html` pricing & features
- [ ] `docs/raycast-integration.md` (if API changed)

### 4. Validate & publish source

```bash
Scripts/publish-to-github.sh
```

This script:

1. Checks for forbidden files (secrets, artifacts)
2. Runs `swift test`
3. Commits changes (if any) and pushes to `main`

### 5. Tag signed release (maintainers)

Official DMG builds are created by the release workflow:

```bash
git tag v1.0
git push origin v1.0
```

Requires GitHub secrets: `DEVELOPER_ID_APPLICATION`, `DEVELOPER_ID_CERTIFICATE`, `DEVELOPER_ID_CERTIFICATE_PASSWORD`, `NOTARY_PROFILE`.

### 6. Verify on GitHub

- [ ] `main` branch updated
- [ ] CI green
- [ ] Release assets uploaded (DMG + appcast.xml)
- [ ] `website/index.html` download link points to latest release

## Sync script reference

```bash
# Dry run — check only, no push
Scripts/publish-to-github.sh --check

# Full publish
Scripts/publish-to-github.sh

# With custom commit message
Scripts/publish-to-github.sh -m "docs: update free/premium table for v1.0"
```

## Repository settings (one-time)

On GitHub (`Tymcio/notchflow`):

1. **Description:** Native macOS notch utility for Apple Silicon — open source, privacy-first
2. **Website:** https://notchflow.eu
3. **Topics:** `macos`, `swift`, `swiftui`, `notch`, `menu-bar`, `apple-silicon`
4. **Actions secrets:** signing & notary credentials for release workflow

## Architecture note

This folder is the **single source of truth** for public code. If you maintain a private fork for experiments, merge back to this repo only content that passes the checklist above. Never mirror private signing keys or `.env` files.
