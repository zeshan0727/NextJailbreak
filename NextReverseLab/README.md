# NEXT Reverse Lab 0.1.1

Prototype iOS 16+ jailbreak-assisted app inventory and reconstruction-prompt generator.

- Displays installed app metadata via private LaunchServices (best effort) and readable application-bundle filesystem discovery.
- Inspects an explicitly selected app's own bundle for Info.plist metadata and at most 5,000 resource entries.
- Imports user-selected screenshots, records user observations, and exports a Markdown reconstruction prompt and the reference screenshots.
- Does NOT decrypt apps, read private data containers or account/keychain data, recover Swift source, trace live app behavior, or reproduce hidden services.

## Build and sign

A push to main affecting NextReverseLab or the dedicated workflow triggers Build and Sign NEXT Reverse Lab, compiling an unsigned IPA on a macOS GitHub Actions runner. It then submits that file to the existing Next Signer - Sign and Publish workflow in this repository. That second workflow owns Apple signing, upload, OTA manifest, and installer listing.

Install portal: https://nextjailbreak.com/install/

Bundle ID: com.nextsolution.nextreverselab
Version: 0.1.1, Build 2

## RootHide / jailbreak notice

Ordinary Apple Ad Hoc signing does NOT grant platform-application or other private filesystem entitlements. Signing and successful installation are separate from verifying jailbreak-assisted bundle access. The first device test must verify which enumeration routes are permitted. If Apple signing removes needed privileges, produce an appropriately entitled TrollStore/RootHide distribution as a separate target, without treating it as ordinary Apple-signed OTA.

Do not assume full device access, decrypted binaries, or recovered view hierarchies.

## Device test

1. Install signed build from the installer after signing workflow succeeds.
2. Open Apps and refresh, then select one app you own or have permission to inspect.
3. Scan its readable application bundle.
4. Import screen captures and describe interactions under Screens.
5. Export prompt plus screenshots under Prompt; share back for independent SwiftUI implementation.

The repository changes are scoped to NextReverseLab and one dedicated workflow; existing installed apps and site content are unchanged.