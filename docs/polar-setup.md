# Polar setup (NotchFlow)

NotchFlow uses [Polar](https://polar.sh) as Merchant of Record for premium sales and license key validation.

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

## 3. Checkout links

After creating products, copy checkout URLs from Polar dashboard and update:

```
website/checkout-urls.js
```

```javascript
var NOTCHFLOW_CHECKOUT = {
  lifetime: "https://buy.polar.sh/polar_cl_…",
  annual: "https://buy.polar.sh/polar_cl_…",
};
```

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
