# NEXT REA Inspector 0.1.0

A separate iOS 16+ test app, bundle ID uk.zeshanbarvi.nextreainspector, to collect read-only app metadata when permitted by the device and export a user-selected IPA to a Mac. The REA reverse-engineering agent itself runs on the computer, not in the iPhone app.

GitHub Actions compiles, checks the bundle/version, ad-hoc signs for TrollStore/jailbreak use, creates an IPA, and publishes to https://nextjailbreak.com/transfer/.

The experimental private LaunchServices API may return zero apps. This test does not bypass iOS sandbox restrictions, extract decrypted binaries, or access app user data. The IPA is not Apple Distribution signed and cannot be installed OTA on ordinary stock iOS.

Source repo for Mac REA integration: https://github.com/morluto/rea
