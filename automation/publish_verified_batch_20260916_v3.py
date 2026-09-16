#!/usr/bin/env python3
"""Final verified batch launcher: NextUp upstream source + Prism replacement for HALO2."""
from automation import publish_verified_batch_20260916_v2 as v2

batch = v2.batch
for target in batch.TARGETS:
    if target.get("name") == "HALO2":
        target.clear()
        target.update({
            "name": "Prism",
            "version": "1.4.2",
            "package_id": "prism",
            "description": "Capture, annotate, and pin screen content on supported jailbroken iOS versions.",
            "urls": ["https://havoc.app/package/prism"],
        })

if __name__ == "__main__":
    raise SystemExit(batch.main())
