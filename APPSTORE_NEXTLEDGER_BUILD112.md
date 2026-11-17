# Next Ledger — App Store submission handoff

Candidate: Next Ledger 1.3.84 Build 112
Source: release/nextledger-1.3.84-build112-appstore-prep
Xcode project / scheme: NextLedger
Bundle ID: com.nextsolution.dailyledger
Widget extension: com.nextsolution.dailyledger.widgets
Apple Team: T52CDY8W32
iCloud Documents: iCloud.com.nextsolution.dailyledger
Minimum OS: iOS 16; 2026 App Store uploads require iOS 26+ SDK.

This is an isolated App Store candidate. It does not replace the verified
Build 111 Ad Hoc version. Keep the existing original app ID to avoid splitting
the installed app or losing access to its local data. The iCloud container is
preserved.

## First steps on Mac

1. Open Terminal and check: xcodebuild -version
2. Check iOS SDK: xcrun --sdk iphoneos --show-sdk-version
3. Clone the selected branch from https://github.com/zeshan0727/NextJailbreak.git
   with branch release/nextledger-1.3.84-build112-appstore-prep.
4. If needed, install XcodeGen: brew install xcodegen
5. In the cloned repository, run:
   zsh scripts/open-nextledger-appstore.sh
6. Xcode: click NextLedger project > NextLedger target > Signing & Capabilities.
   Turn on Automatically manage signing, select Team T52CDY8W32.
   Repeat for the DailyLedgerWidgets extension target.
7. Before archiving, check the existing App Store Connect record: it must use
   com.nextsolution.dailyledger, not com.nextsolution.nextledger. These are
   two different App IDs. Do not silently convert or submit to the wrong app.
8. Select Any iOS Device, Product > Archive, then Organizer >
   Distribute App > App Store Connect > Upload.
   The app AND widget extension need App Store distribution signing.
   The existing Ad Hoc provisioning profiles are not valid for App Store uploads.
9. Internal TestFlight test before public submission.

## Required before App Review

- Verify the App Store Connect record's exact bundle ID first.
- Provide a public, neutral privacy-policy URL, accessible inside the app,
  describing local financial records, iCloud backup and optional third-party AI.
  No public URL has yet been confirmed; do not invent one.
- Complete truthful App Privacy disclosures based on actual data flows.
  This release includes a default-OFF permission before sending bank SMS
  content to OpenAI/DeepSeek for classification.
- Provide real screenshots from Next Ledger on iPhone, product description,
  subtitle, keywords, support contact, age rating, encryption/export compliance,
  pricing/territories and reviewer demo instructions or test data.
- Verify app and widget privacy manifests and signing on Xcode 26+.
- Test financial records, backup/restore, widget size variants and SMS consent.

Do not use obsolete workflows: build-nextledger-appstore.yml (1.3.76/85)
or nextledger-appstore-106-upload.yml (1.3.84/106, wrong App Store bundle ID).
Do not commit private .p12/.p8 credentials, raw provisioning files,
bank details, user messages or private ledger data.
