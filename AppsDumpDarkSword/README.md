# AppsDump DarkSword iOS 17 test port

This branch builds a focused AppsDump-style app-decrypt frontend on top of the open-source LARA DarkSword backend.

## Goal

- iOS 17 DarkSword kernel read/write
- kernel offset initialization/fetch
- sandbox escape
- enumerate installed app bundles
- decrypt the main executable and encrypted frameworks
- package and share the decrypted app as an IPA

## Source / licensing

The exploit, sandbox escape, offsets and decrypt implementation are taken from the upstream `rooootdev/lara` project and remain under its AGPL-3.0 license. The build workflow pins an upstream commit and also uploads the patched source tree with every build artifact.

Upstream credits include opa334 for DarkSword, ChOma and XPF, plus the LARA contributors.

## Test notes

This is the first backend-validation build, not the final AppsDump UI recreation. Do not force-close the app after a successful DarkSword run because upstream documents possible kernel panics while KRW is active. Reboot and retry after an exploit failure.
