# Next Storage v1.0.3 — Photos & Videos

The Media tab enumerates Photos-library assets after read/write Photos permission and determines primary resource byte counts with network downloads disabled. Cloud-only originals can have unavailable sizes. It previews video and photo assets and deletes through `PHPhotoLibrary.performChanges` after user confirmation; physical DCIM files are never unlinked directly. The exact Filza path appears only if a matching on-device DCIM resource is cryptographically verified against the PhotoKit original. When no match is verified, preview remains available without a guessed path.

Build workflow: `.github/workflows/build-nextstorage-103.yml`. Minimum iOS 16.0. Target TrollStore/RootHide. This app never accesses network to upload user photos.
