# Next Automatic iOS Sign Relay — activation package

This is a *review-ready workflow definition*, not an activated workflow.

## Prerequisites

1. Merge the validation helper from https://github.com/zeshan0727/NextJailbreak/pull/280 after review.
2. Store valid certificate and profile in the GitHub Actions secrets already used by Next Signer (`NEXTSIGNER_P12_BASE64`, `NEXTSIGNER_P12_PASSWORD`, `NEXTSIGNER_MOBILEPROVISION_BASE64`). Do not commit any credential.
3. A valid Ad Hoc profile must authorize the app bundle ID and registered devices. iCloud/extension apps require matching explicit profiles and should not use this simple relay.

## Activation

Place `.github/workflows/auto-sign-ios.yml` at the exact path in the repository's `main` branch. Add the following job to a selected app build workflow, initially the Next Post workflow, following the existing `build` job:

```yaml
  auto_sign:
    needs: build
    if: github.event_name != 'pull_request' && github.ref == 'refs/heads/main'
    uses: ./.github/workflows/auto-sign-ios.yml
    with:
      artifact_name: NextPost-1.0.17-Professional-X-Posts
      expected_bundle_id: com.nextsolution.nextpost
```

The caller workflow must have `permissions: contents: write` (Next Post already does). The build job publishes the unsigned TIPA Actions artifact. This relay validates metadata, stages an IPA in the existing `nextsigner-inbox` draft release, and triggers the already existing `nextsigner-sign-publish.yml`. That workflow performs the actual signing and publishes the signed app to the Next Jailbreak install catalog.

## Limitations / safety

- Only trusted `main` runs, never untrusted pull requests.
- This relay intentionally **does not** access or export Apple signing secrets.
- Signing completion is asynchronous in a separate Actions run: a successful relay only means the request was submitted; inspect the signer run for its verified result.
- Existing signer publishes to the Next Jailbreak install catalog, **not** automatically to the NS Transfer index. NS Transfer automatic registration remains a separate integration step.
- The profile must have suitable entitlements. Next Ledger iCloud and apps with extensions require more advanced support.
