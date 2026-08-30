#!/usr/bin/env python3
"""Check what the built deck and guide actually say.

Reads the text straight out of the OOXML rather than shelling out to a
converter. That is not fussiness: the check this replaces piped `pandoc`
into `grep`, pandoc is not installed here, and a missing command prints
nothing -- so `grep -c owner` returned 0 and read exactly like a document
with no mention of the Owner portal in it. A verification that passes
because it never ran is worse than no verification, because somebody
believes it.

Usage:  python3 verify.py
Exits non-zero if either document mentions the Owner portal, or if a
document turns out to hold no text at all -- which is the shape the last
failure took.
"""
import re
import sys
import zipfile
from pathlib import Path

HERE = Path(__file__).parent
DOCS = ['LogicClass-Demo.pptx', 'LogicClass-Feature-Guide.docx']

# <w:t> is Word's text run, <a:t> is PowerPoint's.
TEXT = re.compile(r'<(?:w|a):t[^>]*>(.*?)</(?:w|a):t>', re.S)

# The Owner portal is the platform operator's view -- the schools on the
# platform, their subscriptions, their billing rates. A school reading it
# would be reading every other school's commercial terms.
FORBIDDEN = ['owner', 'billing rate', 'subscription', 'platform_']


def text_of(path: Path) -> str:
    with zipfile.ZipFile(path) as z:
        parts = [n for n in z.namelist() if n.endswith('.xml')]
        found = []
        for name in parts:
            found += TEXT.findall(z.read(name).decode('utf-8', 'ignore'))
    return ' '.join(found)


def main() -> int:
    failures = []
    for name in DOCS:
        path = HERE / name
        if not path.exists():
            failures.append(f'{name}: not built')
            continue

        blob = text_of(path)
        # A document that reads as empty is the failure mode this script
        # exists to catch, so it is an error rather than a silent pass.
        if len(blob) < 2000:
            failures.append(f'{name}: only {len(blob)} characters of text - did it build?')
            continue

        lowered = blob.lower()
        hits = {w: lowered.count(w) for w in FORBIDDEN if w in lowered}
        if hits:
            failures.append(f'{name}: {hits}')
        else:
            print(f'{name}: {len(blob):,} characters, no Owner-portal wording')

    for f in failures:
        print(f'FAIL  {f}', file=sys.stderr)
    return 1 if failures else 0


if __name__ == '__main__':
    raise SystemExit(main())
