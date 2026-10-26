# Next Ledger 1.3.84 (Build 101) — App Store distribution

**Status:** App Store configuration prepared; not uploaded or submitted to Apple.
The locked device build 99 and test build 100 remain unchanged.

## App identity and existing listing

- Existing App Store Connect app bundle identifier: `com.nextsolution.nextledger`
- Version: `1.3.84`, build: `101`
- Distribution team: `T52CDY8W32`
- App Store source: `release/nextledger-1.3.84-build101-appstore`
- The privately installed TrollStore/Ad Hoc builds use **a different ID**,
  `com.nextsolution.dailyledger`. Do not install the App Store build expecting
  in-place access to the other bundle ID's local sandbox; they are separate apps.

## CloudDocuments identity

The current iCloud implementation uses the explicit container
`iCloud.com.nextsolution.dailyledger`. The release retains the same
container in app entitlements, Info.plist, and services, so synced data can be
shared **only if** the distribution App ID `com.nextsolution.nextledger`
has that container assigned in the Apple Developer portal.

**Release blocker:** obtain automatic signing / an App Store distribution
provisioning profile for `T52CDY8W32.com.nextsolution.nextledger`
that explicitly authorizes
`iCloud.com.nextsolution.dailyledger` + CloudDocuments. Verify final
code signature's claims before uploading to Apple.

An Ad Hoc .mobileprovision for the separate `com.nextsolution.dailyledger`
ID is NOT eligible for App Store Connect uploads.

## Compiler requirements (as of October 2026)

Starting April 28, 2026, Apple requires Xcode 26+ and iOS 26+ SDK for uploaded
iOS builds. The preflight workflow
`.github/workflows/nextledger-appstore-101-preflight.yml`
runs on `macos-26`, checks compiler SDK, builds unsigned, and checks
the app bundle ID and exact build version.
The unsigned preflight IPA is **NOT uploadable** to App Store Connect.

## Actual publishing

Preferred privacy-preserving route: Xcode Cloud with automatic signing on
the existing Apple Developer Team. In App Store Connect / Xcode Cloud,
point the existing Next Ledger app workflow at this source branch,
choose App Store distribution, confirm the linked App ID / iCloud container,
archive using Xcode 26+, and upload to App Store Connect.
Alternatively, on a secure Apple-authenticated Mac archive/export with
App Store distribution signing and use Apple's Transporter.
Do not commit distribution certificates, passwords, profiles, API keys,
or private customer ledger JSON to this GitHub repo.

The app previously required additional Apple verification; that separate
App Store Connect review/account status must be resolved before submission.
After upload, wait for Apple processing, attach the Build 101 binary to the
correct listing, review metadata, privacy answers, screenshots, age rating,
and App Review information, then explicitly submit for review.

Note: The RootHide SMS daemon is distributed outside the App Store and cannot
be relied on for stock iPhones. Verify all displayed App Store features behave
on a non-jailbroken device without the daemon; treat nonfunctional
jailbreak-only controls as an App Review risk.

## User data safety

Never uninstall or replace the populated `com.nextsolution.dailyledger`
app without a readable exported JSON backup. A separate `com.nextsolution.nextledger`
bundle ID receives a different iOS app container; shared iCloud Documents
access may allow a deliberate data import/sync but does not magically migrate
the local sandbox.
