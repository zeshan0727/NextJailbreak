"""Apply the verified v1.4 AI library-repair delta to v1.3 sources."""
from pathlib import Path
import base64
import json
import lzma
import re

root = Path(__file__).resolve().parent
encoded = ''.join((root / 'patch_v1_4.b64').read_text(encoding='ascii').split())
payload = json.loads(lzma.decompress(base64.b64decode(encoded)))

def apply_unified(original: str, patch: str) -> str:
    src = original.splitlines(keepends=True)
    lines = patch.splitlines(keepends=True)
    out = []
    oldpos = 0
    i = 0
    while i < len(lines):
        line = lines[i]
        if not line.startswith('@@ '):
            i += 1
            continue
        match = re.match(r'@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@', line)
        if match is None:
            raise ValueError('Invalid patch hunk: ' + line)
        start = int(match.group(1)) - 1
        if start < oldpos:
            raise ValueError('Overlapping delta hunks')
        out.extend(src[oldpos:start])
        oldpos = start
        i += 1
        while i < len(lines) and not lines[i].startswith('@@ '):
            pline = lines[i]
            i += 1
            if pline.startswith('\\ No newline'):
                continue
            if pline.startswith(' '):
                if oldpos >= len(src) or src[oldpos] != pline[1:]:
                    raise ValueError('Patch context failed')
                out.append(src[oldpos])
                oldpos += 1
            elif pline.startswith('-'):
                if oldpos >= len(src) or src[oldpos] != pline[1:]:
                    raise ValueError('Patch removal failed')
                oldpos += 1
            elif pline.startswith('+'):
                out.append(pline[1:])
            else:
                raise ValueError('Invalid patch line')
    out.extend(src[oldpos:])
    return ''.join(out)

for name, patch in payload['diffs'].items():
    target = root / name
    target.write_text(apply_unified(target.read_text(encoding='utf-8'), patch), encoding='utf-8')
for name, content in payload['new'].items():
    target = root / name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding='utf-8')
print('Applied v1.4 AI library repair:', len(payload['diffs']), 'updated and', len(payload['new']), 'new files')
