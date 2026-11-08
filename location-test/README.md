# NEXT Jailbreak — private device/location research test

The regular location test is at `https://nextjailbreak.com/location-test/`.
The owner dashboard is at `https://nextjailbreak.com/location-test/admin/`.

## What the test collects
- A location reading only after the person taps **Get my location**, approves the browser's location prompt, and explicitly submits.
- A coarse device summary (iPhone/iPad/Android/Mac/Windows category, browser-reported OS, browser, screen size, browser language, browser timezone, touch capability) only after the person requests it and explicitly submits.
- No serial numbers, Apple IDs, contact information, stealth location tracking, device fingerprint IDs, raw user agent, or precise iPhone hardware-model identifiers.

Device information is displayed locally first. New records store the GPS coordinates and the approved device summary in Cloudflare D1 for 24 hours, without placing them in public HTML. Old test results continue to work, but cannot retroactively include device details.

## Lists and privacy

**My recent tests** appears on the same device and keeps the private result-link keys in that browser's local storage. Other browsers will not automatically have this local history; anyone with a copied private result link can open that single record.

**Owner dashboard** has a central list with timestamp and device category; selecting a row retrieves its GPS coordinates and device summary. The API requires a separately configured high-entropy Worker secret, never accepts an unauthenticated listing, and does not embed a secret in a URL.

### One-time owner setup (Cloudflare)

1. Sign in to Cloudflare dashboard for the account that deploys `nextjailbreak-edge`.
2. Workers & Pages → `nextjailbreak-edge` → Settings → Variables and Secrets.
3. Create a **secret** named `LOCATION_ADMIN_TOKEN`, with a unique random value at least 32 characters long (use a password manager's secure generator). Do **not** use a public variable.
4. Save/deploy the secret. Keep it in a password manager, not in GitHub code or this chat.
5. Open `https://nextjailbreak.com/location-test/admin/` and enter that key when prompted.

The GitHub deployment uses the existing Cloudflare D1 binding. Existing secret bindings should be retained during subsequent deployments; re-check the secret after major worker changes.

## Retention and access

- Records are excluded from API queries once 24 hours have elapsed.
- An hourly GitHub Action cleans up expired coordinates and their device summaries.
- The owner can delete any active entry. The person submitting can delete their own record through the private result link.
- The central list returns at most 100 active entries and does **not** send coordinates until a row is selected.
- The page has `noindex`, no ads and no analytics scripts.
- Never share the private result link or owner password publicly.

## Manual test

1. On an iPhone, open the test PDF or go to the page in Safari.
2. Tap **Detect basic device info**; verify it shows general device information. Exact hardware model may be unavailable.
3. Tap **Get my location**, allow the permission prompt, and check the GPS preview.
4. Select the explicit consent checkbox and tap **Submit**.
5. Check the individual private result link and **My recent tests** list.
6. In the owner dashboard, enter `LOCATION_ADMIN_TOKEN`, refresh, select the new session, and check GPS plus device fields.
7. Delete the test and confirm it disappears from the list.

Do not test location capture on anyone else's device without their knowledge and affirmative consent.
