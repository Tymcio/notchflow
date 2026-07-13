# Polar setup (NotchFlow)

NotchFlow uses [Polar](https://polar.sh) as Merchant of Record for premium sales and license key validation.

Powiązane: **[polar-rejestracja.md](polar-rejestracja.md)** (pełna instrukcja założenia konta, organizacji, KYC i wypłat).

## 1. Create Polar organization

1. Sign up at [polar.sh](https://polar.sh)
2. Create organization (e.g. **NotchFlow**)
3. Copy **Organization ID** from Settings → General

## 2. Products & benefits

Create two products (or one product with two prices):

| Product | Type | Price | License benefit |
|---------|------|-------|-----------------|
| **Premium Annual** | Subscription, yearly | €12/year | License keys, expires after 1 year |
| **Premium Lifetime** | One-time | €24 | License keys, no expiration |

For each product, add a **License Keys** benefit:

- Prefix: `NOTCHFLOW_` (optional branding)
- **Activation limit: 2** (required — app enforces per-device activation)
- Allow customers to deactivate devices in Polar portal (recommended)

## 3. Checkout integration (website)

NotchFlow uses **Checkout Links** — persistent Polar URLs that create a checkout session on visit. No backend or Polar SDK on the website.

### 3.1 Create Checkout Links (Polar dashboard)

**Products → Checkout Links → New Link** — create **two** links (one per product).

| Setting | Lifetime link | Annual link |
|---------|---------------|-------------|
| **Product** | `NotchFlow Premium Lifetime` only | `NotchFlow Premium Annual` only |
| **Label** | `NotchFlow Lifetime` | `NotchFlow Annual` |
| **Discount** | — | — |
| **Allow discount codes** | Off (unless you run promos) | Off |
| **Success URL** | `https://notchflow.eu/pricing/?purchased=lifetime` | `https://notchflow.eu/pricing/?purchased=annual` |
| **Return URL** | `https://notchflow.eu/pricing/` | `https://notchflow.eu/pricing/` |
| **Trial** | — | Off (no trial for v1.0) |
| **Metadata** | optional: `plan=lifetime` | optional: `plan=annual` |

For Polish pricing page redirects, you can instead use:

- `https://notchflow.eu/pl/pricing/?purchased=lifetime`
- `https://notchflow.eu/pl/pricing/?purchased=annual`

Or keep English pricing URLs for both — the success banner detects `/pl/` and shows Polish copy.

After saving, copy each link URL (`https://buy.polar.sh/polar_cl_…`).

### 3.2 Wire URLs in the repo

Update `website/checkout-urls.js`:

```javascript
var NOTCHFLOW_CHECKOUT = {
  lifetime: "https://buy.polar.sh/polar_cl_XXXXX",
  annual: "https://buy.polar.sh/polar_cl_YYYYY",
};
```

The script finds every `[data-polar-checkout="lifetime|annual"]` button on:

- `website/index.html`
- `website/pricing/index.html`
- `website/pl/index.html`
- `website/pl/pricing/index.html`

No other website changes are required for checkout.

### 3.3 Optional: branding

**Settings → Branding** in Polar: logo and accent color for the hosted checkout page. Matches notchflow.eu visually.

### 3.4 Customer flow after payment

1. Customer clicks **Buy** on notchflow.eu → Polar checkout (card, Apple Pay, etc.)
2. Polar emails **license key** (`NOTCHFLOW_…`)
3. Success URL redirects to pricing with a thank-you banner
4. Customer opens NotchFlow → **Settings → License** → paste key → **Activate**

License validation is in the macOS app (`PolarLicenseClient.swift`), not on the website.

## 4. App configuration

Set organization ID for license validation (public, safe in the app):

**Release builds** (`Scripts/sign-and-notarize.sh` / CI):

```bash
export POLAR_ORGANIZATION_ID="your-uuid-here"
ENFORCE_LICENSE=1 Scripts/package_app.sh
```

**Local development:**

```bash
export POLAR_ORGANIZATION_ID="your-uuid-here"
export NOTCHFLOW_ENFORCE_LICENSE=1
Scripts/compile_and_run.sh
```

Or inject into `Info.plist` via `package_app.sh` (automatic when `POLAR_ORGANIZATION_ID` is set).

## 5. Test flow

1. Buy test product (Polar sandbox / test mode if available)
2. Copy license key from Polar customer portal email
3. NotchFlow → Settings → License → paste key → **Activate**
4. Confirm premium features unlock
5. Quit app, disable network briefly — grace period (14 days) should keep premium
6. Activate same key on second Mac — should work
7. Third Mac — should show activation limit error

## API reference

- Activate: `POST https://api.polar.sh/v1/customer-portal/license-keys/activate`
- Validate: `POST https://api.polar.sh/v1/customer-portal/license-keys/validate`

Implementation: `Sources/NotchFlow/Licensing/PolarLicenseClient.swift`

## Privacy & legal

Website privacy/terms already reference Polar. Polar privacy policy: https://polar.sh/legal/privacy
