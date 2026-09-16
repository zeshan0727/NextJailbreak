#!/usr/bin/env python3
"""Final verified batch launcher: NextUp upstream source + Crescendo replacement for HALO2."""
from automation import publish_verified_batch_20260916_v2 as v2

batch = v2.batch
for target in batch.TARGETS:
    if target.get("name") == "HALO2":
        target.clear()
        target.update({
            "name": "Crescendo",
            "version": "1.1.1",
            "package_id": "com.yves.crescendo",
            "description": "Brings the volume slider back to the Lock Screen and Dynamic Island on supported jailbroken iOS versions.",
            "urls": [
                "https://github.com/Yves000/Crescendo",
                "https://raw.githubusercontent.com/Yves000/Crescendo/main/control",
            ],
            "github": [("Yves000", "Crescendo")],
        })

if __name__ == "__main__":
    raise SystemExit(batch.main())
