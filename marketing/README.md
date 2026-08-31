# Marketing materials

Two deliverables for demoing LogicClass to a school, and the scripts that
build them.

| File | What it is |
|---|---|
| `LogicClass-Demo.pptx` | 38-slide demo deck, with speaker notes on every slide |
| `LogicClass-Feature-Guide.docx` | 52-page reference: every screen and every button, portal by portal |
| `LogicClass-Demo.pdf`, `LogicClass-Feature-Guide.pdf` | The same two, for sending to somebody who will not open Office |

## The Owner portal is not in either of them

The Owner portal is the platform operator's view -- the schools on the
platform, their subscriptions, their billing rate and the revenue across
all of them. It is not part of what a school buys, and a school seeing it
would be seeing every other school's commercial terms. Both documents
describe the nine school-facing portals and stop there.

There is a check for this:

```sh
python3 verify.py
```

It reads the text straight out of the OOXML of both files and exits
non-zero if either mentions the Owner portal -- or if either turns out to
hold no text at all.

That last condition is there because of how this check failed the first
time. It used to be `pandoc -t markdown ... | grep -ic owner`. Pandoc is
not installed in the environment these were built in, a missing command
prints nothing, and `grep -c` over nothing returns 0 -- which reads
exactly like a document with no mention of the Owner in it. The check
passed twice without ever running. A verification nobody can tell has
stopped working is worse than none, because somebody believes it.

## Rebuilding them

```sh
npm install                     # pptxgenjs, docx, react-icons, sharp
node deck.js                    # -> LogicClass-Demo.pptx
node guide.js                   # -> LogicClass-Feature-Guide.docx
python3 verify.py               # both, checked
```

Both generators write beside themselves rather than into the shell's
working directory. Run from the repository root, a bare relative path
drops the document there instead -- leaving the copy in `marketing/`
stale while looking like it was just rebuilt, which is exactly what
happened once.

`lib.js` holds the deck's slide components (headings, card grids, row
lists, callouts) and its palette; `icons.js` rasterises Feather icons to
PNG so they can be embedded. Edit the content in `deck.js` and `guide.js`
-- both are one file each, read top to bottom in slide/section order.

To re-render for a visual check:

```sh
soffice --headless --convert-to pdf LogicClass-Demo.pptx
pdftoppm -jpeg -r 100 LogicClass-Demo.pdf slide
```

## Keeping them true

Every feature claim in both documents came from the code, not from the
docs -- screen by screen, button label by button label. When a feature
changes, the line to check is the one naming the button.

There is a third document, `docs/38-demo-script.md`, which is the running
order for the demo itself -- what to open, in what sequence, and what to
say. It is internal: it covers the Owner portal, and it says in as many
words not to open that portal in front of a school.

Rebuild both after any feature change and read the pages that moved.
Section headings in the guide carry `pageBreakBefore` rather than an
explicit break paragraph: a standalone break is itself a line, so a
section whose content happens to end at the page boundary used to push
that empty paragraph onto a sheet of its own and the reader got a blank
page. Attaching the break to the next heading cannot do that.
