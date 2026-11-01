# Next automatic IPA signing — integration plan

## Current architecture (verified in repository)

- The existing `.github/workflows/nextsigner-sign-publish.yml` signs and publishes IPA files.
- `.github/workflows/nextsigner-sign-only.yml` supports signing without publishing.
- `NextSigner/NextSigner/SigningProfileService.swift` securely uploads the certificate, password and provisioning profile as encrypted GitHub Actions secrets.
- Signed install binaries are published using the existing Cloudflare R2 integration. NS Transfer's separate index is `transfer/index.json`.

## One-time secret configuration

Configure through Next Signer > Signing Profile or in the private GitHub Actions Secrets settings (never commit values):

- `NEXTSIGNER_P12_BASE64`
- `NEXTSIGNER_P12_PASSWORD`
- `NEXTSIGNER_MOBILEPROVISION_BASE64`
- `CLOUDFLARE_R2_ACCESS_KEY_ID`
- `CLOUDFLARE_R2_SECRET_ACCESS_KEY`

For explicit App IDs with specialized entitlements, add app-specific profiles. Do **not** reuse a wildcard profile for iCloud Documents or Network Extensions. An Ad Hoc profile must include the destination device(s).

## Trusted build -> signer behavior

1. Only successful, trusted `main` app-build runs are eligible. Do not expose the signing credentials to pull-request builds or untrusted code.
2. Retrieve the build artifact by its exact GitHub Actions artifact name.
3. Run `.github/scripts/auto-sign-ios.py inspect` with `ARTIFACT_DIRECTORY`, `EXPECTED_BUNDLE_ID`, `RUNNER_TEMP` and `GITHUB_ENV`. It checks the package, bundle identity, version, checksum, app extensions and exported entitlements, and produces an unchanged IPA input for the signer.
4. Select the correct private Ad Hoc profile, then use the existing `nextsigner-icloud-entitlements.py prepare` and `verify` validation, and the pinned `zhlynn/zsign` signer.
5. Reinspect the signed package with `auto-sign-ios.py verify` and calculate SHA-256.
6. Upload a signed Actions artifact. If the signing and R2 configuration is valid, publish to the public file bucket, verify HTTP download, and update `transfer/index.json` with an accurate signed-package label.
7. Never overwrite the original unsigned `.tipa` for TrollStore, never rename installed applications, and never silently strip app capabilities.

## Activation status

The validation helper is available on this development branch. The automation still requires a GitHub Actions workflow to call it after a successful build. It must **not** be described as enabled until that workflow is committed to `.github/workflows/`, the Actions secrets are configured, and a run successfully signs and publishes a test IPA.

A first pilot on a standard app such as Next Post is safer than automatically signing all existing apps. Next Ledger uses iCloud and needs an explicit matching profile; Next Multi Browser has an extension and needs extension-specific signing.
