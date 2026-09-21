#!/bin/bash
set -euo pipefail
cp tmp-build-1333/build.sh "$RUNNER_TEMP/build-1333-fixed.sh"
python3 - <<'PY'
from pathlib import Path
import os
p=Path(os.environ['RUNNER_TEMP'])/'build-1333-fixed.sh'
s=p.read_text()
old='''# Reconstruct exact 1.0.16 tweak source, then add missed-reminder scheduler.
awk '/^brew install dpkg ldid/{exit} {print}' tmp-build-1331/build.sh > "$R/reconstruct-tweak1016.sh"
bash "$R/reconstruct-tweak1016.sh"
TROOT="$R/nqrsrc"
'''
new='''# Preserve the already-validated app package because the historical tweak
# reconstruction script clears $RUNNER_TEMP/out.
cp "$R/out/NextReminder_1.3.32_Unsigned.tipa" "$R/NextReminder_1.3.32_Unsigned.tipa"

# Reconstruct exact 1.0.16 tweak source, stopping before its historical
# post-reconstruction grep block. This build performs its own stricter guards below.
awk '/^grep -q .Version: 1.0.16/{exit} {print}' tmp-build-1331/build.sh > "$R/reconstruct-tweak1016.sh"
bash "$R/reconstruct-tweak1016.sh"
mkdir -p "$R/out"
cp "$R/NextReminder_1.3.32_Unsigned.tipa" "$R/out/NextReminder_1.3.32_Unsigned.tipa"
TROOT="$R/nqrsrc"
'''
if old not in s:
    raise SystemExit('tweak reconstruction block not found')
p.write_text(s.replace(old,new,1))
PY
exec bash "$RUNNER_TEMP/build-1333-fixed.sh"
