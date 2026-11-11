# Next Ledger 1.3.84 (106) — App Review submission checklist

This document is review-preparation information **outside the iOS app bundle**. Do not submit the old 1.3.76 (85) screenshots or attach private-signing material.

## Reason for prior rejection
Apple rejected 1.3.76 (85) on 2026-08-20 with **Guideline 2.1 — Information Needed — New App Submission**. Apple's message requires the seven items below. This was a request for review information, not an allegation of prohibited branding.

## Mandatory information (provide accurate facts, not approximations)
1. **Physical-device video:** link to an accessible, unedited walkthrough captured on a physical supported iPhone running the latest public iOS available when submitting. Begin at app launch. Show realistic data entered into accounts; income, expense, transfers, budgets, reports, iCloud backup/restore, and any optional AI features presented. Include all permission prompts; if registration, purchase, subscriptions, user-generated content, moderation or deletion flows exist, record them too. Verify all features work on stock, non-jailbroken iOS. Never expose private API keys or personal financial information in the video.
2. **Device testing:** provide actual device models, exact iOS versions, and date tested. Do not reuse the jailbroken iOS 16 test as evidence of testing the latest iOS.
3. **Functions and audience:** Next Ledger is a personal-finance and bookkeeping application for individuals who want to record income, spending, account movements, monthly plans, and on-device reports. It is not a bank, wallet or payment processor. Confirm this description against the final binary and screenshots.
4. **Access/setup:** explain first-launch flow and how to create a sample account and transactions. State whether sign-in is necessary. Provide test credentials only through App Review Information when actually required. Show how to reach the main tabs and iCloud backup / restore.
5. **External services:** disclose Apple iCloud Drive (CloudDocuments backup/restore and cross-device sync) and the optional OpenAI and DeepSeek API services (the app source includes API clients and user-entered API-key handling). Disclose any other production dependencies discovered in final QA; do not claim that AI operates without a key if it does not.
6. **Regional differences:** test and state any differences in availability, currency handling, language, services, or content by region. Do not claim global parity without testing.
7. **Regulated / third-party material:** if no financial account access, fund transmission, regulated advice, or protected third-party content is offered, clearly explain this. Supply documentary authorizations if a production feature does require them.

## Release gate beyond Guideline 2.1
- Use the genuine 1.3.84 (106) source, not old 1.3.76 or main-branch 1.3.77.
- App Store Bundle ID is `com.nextsolution.nextledger`; preserve its authorized shared iCloud container `iCloud.com.nextsolution.dailyledger`.
- **No Next Jailbreak or associated website links/brand** in app UI, compiled Swift strings, embedded resources, PDFs produced by the app, app review screenshots, App Store descriptions, or linked Support/Privacy pages.
- Change any old support/privacy URLs hosted on a jailbreak-focused website to independently hosted, truthful Next Ledger legal/help pages before submitting. Do not fabricate a URL; verify the new pages work publicly.
- The app icon and screenshots must depict the real finance app rather than other software or a generic splash screen.
- Confirm every visible function works on standard App Store iOS without jailbreaking, private entitlements, or companion software unavailable to App Store users. Remove/disable such functionality honestly if it does not.
- Run the App Store preflight and audit **the final signed IPA**. Finish device QA in TestFlight, then update review notes and upload the video.
- Do not resubmit until all seven of Apple's requested items are supplied.

## Draft App Review note (complete missing evidence before using)
Next Ledger 1.3.84 (Build 106) is an iPhone personal finance and bookkeeping app. Users record income, expenses, transfers and account balances, build monthly budgets, and view or export summaries and reports. Apple iCloud Documents is used for optional backups, restores and device sync. Optional AI assistance can use OpenAI and DeepSeek APIs with user-provided API keys. The app itself does not hold or transfer customer funds.

Physical-device walkthrough recording: [ADD ACCESSIBLE VIDEO LINK]
Tested hardware and iOS builds: [ADD ACTUALLY TESTED MODELS AND VERSIONS]
First-use/demo instructions: [ADD VERIFIED STOCK-iOS WALKTHROUGH]
Regional differences: [ADD VERIFIED STATEMENT]
Access credentials, if any: [ADD IN SECURE APP REVIEW FIELD]
Required authorizations, if any: [ADD DOCUMENTATION OR ACCURATE N/A]
