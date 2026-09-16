#!/usr/bin/env python3
"""Verified batch launcher with strengthened NextUp 3 first-party evidence."""
from automation import publish_verified_batch_20260916 as batch

for target in batch.TARGETS:
    if target.get("name") == "NextUp 3":
        target["description"] = "See and skip the upcoming track from the now-playing UI across supported media apps and surfaces."
        target["urls"] = [
            "https://github.com/Yves000/NextUp3",
            "https://raw.githubusercontent.com/Yves000/NextUp3/main/README.md",
            "https://raw.githubusercontent.com/Yves000/NextUp3/main/control",
            "https://havoc.app/package/nextup3",
        ]
        target["github"] = [("Yves000", "NextUp3")]
        target.pop("scope_note", None)

if __name__ == "__main__":
    raise SystemExit(batch.main())
