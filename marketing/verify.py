#!/usr/bin/env python3
"""Check what the built deck and guide actually say.

Reads the text straight out of the OOXML rather than shelling out to a
converter. That is not fussiness: the check this replaces piped `pandoc`
into `grep`, pandoc is not installed here, and a missing command prints
nothing -- so `grep -c owner` returned 0 and read exactly like a document
with no mention of the Owner portal in it. A verification that passes
because it never ran is worse than no verification, because somebody
believes it.

It also checks the counts the README quotes back at the reader. Those
drift the moment either document grows, and a README that says 52 pages
over a 58-page guide is the same kind of wrong as a stale feature claim:
small, and true-looking until somebody counts.

Usage:  python3 verify.py
Exits non-zero if either document mentions the Owner portal, if a
document turns out to hold no text at all -- which is the shape the last
failure took -- or if the README's counts no longer match what was built.
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


def readme_counts(deck: Path) -> list:
    """Hold the README's own numbers to the built artefacts.

    The slide count is read out of the deck. The page count is read from
    the generated PDF, because pages are a rendering property -- the
    .docx has no page count until something lays it out.
    """
    readme = (HERE / 'README.md').read_text(encoding='utf-8')
    problems = []

    with zipfile.ZipFile(deck) as z:
        slides = len([n for n in z.namelist()
                      if re.match(r'ppt/slides/slide\d+\.xml$', n)])
    claimed = re.search(r'(\d+)-slide demo deck', readme)
    if not claimed:
        problems.append('README no longer states a slide count')
    elif int(claimed.group(1)) != slides:
        problems.append(
            f'README says {claimed.group(1)} slides, the deck has {slides}')

    pdf = HERE / 'LogicClass-Feature-Guide.pdf'
    claimed_pages = re.search(r'(\d+)-page reference', readme)
    if not claimed_pages:
        problems.append('README no longer states a page count')
    elif pdf.exists():
        # /Type /Page, not /Pages, and not /Page followed by a letter.
        blob = pdf.read_bytes()
        pages = len(re.findall(rb'/Type\s*/Page[^s]', blob))
        if pages and int(claimed_pages.group(1)) != pages:
            problems.append(
                f'README says {claimed_pages.group(1)} pages, the guide PDF has {pages}')
        elif pages:
            print(f'README: {slides} slides and {pages} pages, both as claimed')
    return problems


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

    deck = HERE / DOCS[0]
    if deck.exists():
        failures += readme_counts(deck)

    for f in failures:
        print(f'FAIL  {f}', file=sys.stderr)
    return 1 if failures else 0


if __name__ == '__main__':
    raise SystemExit(main())
