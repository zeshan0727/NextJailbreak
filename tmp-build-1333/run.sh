#!/bin/bash
set -euo pipefail

cp tmp-build-1333/build.sh "$RUNNER_TEMP/build-1333-fixed.sh"

python3 - <<'PY'
from pathlib import Path
import os
p=Path(os.environ['RUNNER_TEMP'])/'build-1333-fixed.sh'
s=p.read_text()
start=s.index('# Reconstruct exact 1.0.16 tweak source, then add missed-reminder scheduler.')
end=s.index('TROOT="$R/nqrsrc"', start)+len('TROOT="$R/nqrsrc"')
new=r'''# Preserve the already-validated app package.
cp "$R/out/NextReminder_1.3.32_Unsigned.tipa" "$R/NextReminder_1.3.32_Unsigned.tipa"

# Reconstruct the verified 1.0.15 tweak source explicitly, then promote it to
# the verified 1.0.16 persistent-report scheduler baseline. This avoids the
# historical builder's post-reconstruction guards clearing the combined output.
rm -rf "$R/nqrsrc" "$R/theos-rh"
mkdir -p "$R/nqrsrc"
cat tmp-build/nqr1012/part-* > "$R/nqr.b64"
python3 - <<'PYBASE'
import base64,os,pathlib
r=pathlib.Path(os.environ['RUNNER_TEMP'])
(r/'nqr.tar.xz').write_bytes(base64.b64decode((r/'nqr.b64').read_bytes()))
PYBASE
echo 'eba18cc3ee4117e3e190441ce3533e10613a182aa610a3c92756c72a84cfd757  '"$R/nqr.tar.xz" | shasum -a 256 -c -
tar -xJf "$R/nqr.tar.xz" -C "$R/nqrsrc"

cat tmp-build-1325/patch/tweak-* > "$R/tweak1014.patch.xz.b64"
base64 -D < "$R/tweak1014.patch.xz.b64" > "$R/tweak1014.patch.xz"
xz -dc "$R/tweak1014.patch.xz" > "$R/tweak1014.patch"
patch -d "$R/nqrsrc" -p4 < "$R/tweak1014.patch"

base64 -D < tmp-build-1330/tweak1015.patch.xz.b64 > "$R/tweak1015.patch.xz"
xz -dc "$R/tweak1015.patch.xz" > "$R/tweak1015.patch"
patch -d "$R/nqrsrc" -p1 < "$R/tweak1015.patch"

cp tmp-build-1331/PersistentReportScheduler.m "$R/nqrsrc/PersistentReportScheduler.m"

python3 - <<'PYPERSIST'
from pathlib import Path
import os,re
root=Path(os.environ['RUNNER_TEMP'])/'nqrsrc'

p=root/'Makefile'
s=p.read_text()
lines=s.splitlines()
for i,line in enumerate(lines):
    if line.startswith('NextQuickReminder_FILES ='):
        if 'PersistentReportScheduler.m' not in line:
            line=line.replace('PendingReportSender.m','PendingReportSender.m PersistentReportScheduler.m',1)
        lines[i]=line
        break
else:
    raise SystemExit('NextQuickReminder_FILES line missing')
p.write_text('\n'.join(lines)+'\n')

p=root/'Tweak.xm'
s=p.read_text()
if 'NQRStartPendingReportAutomationScheduler();' in s:
    s=s.replace('NQRStartPendingReportAutomationScheduler();','NQRStartPersistentReportScheduler();',1)
if 'NQRStartPersistentReportScheduler();' not in s:
    raise SystemExit('Persistent scheduler start insertion point missing')
decl='extern "C" void NQRStartPersistentReportScheduler(void);\n'
if decl not in s:
    pos=s.find('\n')
    s=s[:pos+1]+decl+s[pos+1:]
p.write_text(s)

p=root/'control'
s=p.read_text()
s=re.sub(r'^Version:\s*1\.0\.15\s*$','Version: 1.0.16',s,flags=re.M)
if 'Version: 1.0.16' not in s:
    raise SystemExit('Unable to promote tweak baseline to 1.0.16')
p.write_text(s)
PYPERSIST

mkdir -p "$R/out"
cp "$R/NextReminder_1.3.32_Unsigned.tipa" "$R/out/NextReminder_1.3.32_Unsigned.tipa"
TROOT="$R/nqrsrc"'''
s=s[:start]+new+s[end:]
p.write_text(s)
PY

exec bash "$RUNNER_TEMP/build-1333-fixed.sh"
