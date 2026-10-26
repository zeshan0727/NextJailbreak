# NextCompat 1.0 — experimental iOS 16 missing-symbol fix

A local SwiftUI utility to patch one **selected, decrypted** IPA at a time. Target: iOS 16.0 / TrollStore; no need to alter RootHide, other apps, or Apple's system frameworks.

## Workflow

1. Export a *decrypted* IPA using a tool you trust, then import it into NextCompat.
2. Import the app's `.ips` crash report with `DYLD: Symbol missing`, or enter the exact missing symbol manually.
3. NextCompat validates that the symbol exists as exactly one strong import in the main executable's `LC_DYLD_CHAINED_FIXUPS` table.
4. Select **Create patched IPA**. NextCompat flips only that import's weak-binding bit and checks the patched binary. Original IPA is preserved.
5. Share the output `.ipa` to TrollStore to install; TrollStore must have its `ldid` signing component. Back up the app's data before replacing an installed app.

## Scope and limitations

- Imports only: the built-in app selector is the imported IPA. An installed-app enumeration / jailbreak injector is **not** included, to avoid private API entitlements and startup-time dyld restrictions.
- Handles ARM64, unencrypted 64-bit Mach-O main executables using chained-import formats 1, 2, 3. Fat Mach-O, classic dyld bind opcodes and encrypted executables are rejected without editing.
- Weak-linking can solve dyld's missing-symbol launch failure. It does **not** supply the missing iOS API. If the application accesses the resulting null pointer without checking availability, a runtime crash can still occur.
- The exported app no longer has its original App Store signature. Install with TrollStore, not normal App Store installation. Replacing an app may change entitlements and impact notifications, keychain access, sign-in, or payments.
- Processing and originals are stored in the app's Documents/Application Support and stay on-device. IPA processing uses the ZIPFoundation library. An IPA may need ~2x its expanded size in free storage during work.
- This is a first test build, not a guaranteed universal repair. **Do not** apply fixes to banking or other sensitive apps without a specific diagnosis.

## Build (GitHub Actions)

The workflow uses macOS/Xcode + XcodeGen and produces an unsigned `.tipa` artifact for TrollStore. Import and patch operations run entirely on-device once NextCompat is installed.

To build manually: `brew install xcodegen`, `xcodegen generate --spec project.yml`, then build the Xcode scheme `NextCompat` for generic iOS with signing disabled. Packaging for TrollStore is handled by GitHub Actions.

## Tested

The chaining-fixup weak bit logic is based on the successful KFC 10.68.4 patch observed on iOS 16.0. Source syntax is locally parse-checked; actual iOS build and on-device use must be validated on a GitHub macOS runner and your iPhone.

