#!/usr/bin/env python3
"""Publish exactly one verified original-source article: SCMusicPlus v24.9.1."""
from automation import publish_verified_batch_20260916 as batch

batch.TARGETS = [{
    "name": "SCMusicPlus",
    "version": "24.9.1",
    "package_id": "scmusicplus",
    "description": "SoundCloud jailbreak tweak maintained by Rov3r, with a rootless package release for SoundCloud 7.55.0.",
    "urls": [
        "https://github.com/Rov3r/scmusicplus/releases/tag/v24.9.1",
        "https://github.com/Rov3r/scmusicplus",
        "https://raw.githubusercontent.com/Rov3r/scmusicplus/main/README.md",
        "https://raw.githubusercontent.com/Rov3r/scmusicplus/main/Tweak.x",
        "https://raw.githubusercontent.com/Rov3r/scmusicplus/main/control",
    ],
    "github": [("Rov3r", "scmusicplus")],
    "scope_note": (
        "SOURCE-SCOPE NOTE: Cover only SCMusicPlus v24.9.1 facts documented by Rov3r in the official GitHub release and repository. "
        "The release was published September 19, 2026 and explicitly supports SoundCloud app version 7.55.0. "
        "The changelog says it removes ads and hides the Upgrade tab. It explicitly says the update does not address login issues. "
        "The developer also says IPA files are no longer included in releases and rootless DEB packages will be provided instead. "
        "Do not imply that login problems are fixed, do not provide unofficial or modified IPA downloads, and do not expand compatibility beyond what the original source states. "
        "VISUAL NOTE: inspect the official GitHub repository/release first. If no developer screenshot or release artwork is available, the project's own GitHub/OpenGraph project visual may be used as the authentic source-page fallback and must be cached locally and credited to the original GitHub project."
    ),
}]

if __name__ == "__main__":
    raise SystemExit(batch.main())
