#!/usr/bin/env python3
"""Draws the demo school's seal and prints it as a data URI.

The demo needs *a* school logo on file, because the ID card now prints the
school's logo as its background and a demo with no logo demonstrates the
absence of the feature. It cannot be one of the bundled brand SVGs: the
card rasterises its watermark (`UploadedImage`, `pdfImage`), and neither
decodes SVG.

Generated rather than committed as a binary blob for the same reason the
brand assets are: the geometry is reviewable, and anyone can regenerate
it. Output goes into demo_store.dart as a data URI, which is exactly the
shape a real upload takes in demo mode.

    python3 tool/generate_demo_seal.py

Deliberately generic -- a ring, a star and a laurel. It stands in for
whatever a school actually uploads, and being obviously a placeholder is
better than looking like a real institution's crest.
"""

import base64
import struct
import zlib

SIZE = 256
SS = 3  # supersampling factor, for edges that do not look sawn

NAVY = (61, 74, 122, 255)
CREAM = (247, 245, 238, 255)
CLEAR = (0, 0, 0, 0)


def _star_points(cx, cy, outer, inner, points=5):
    """A five-pointed star as a polygon, first point straight up."""
    import math

    pts = []
    for i in range(points * 2):
        r = outer if i % 2 == 0 else inner
        a = -math.pi / 2 + i * math.pi / points
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def _inside(poly, x, y):
    """Ray casting. Good enough for a convex-ish star at this size."""
    hit = False
    n = len(poly)
    for i in range(n):
        x0, y0 = poly[i]
        x1, y1 = poly[(i + 1) % n]
        if (y0 > y) != (y1 > y):
            xint = (x1 - x0) * (y - y0) / (y1 - y0) + x0
            if x < xint:
                hit = not hit
    return hit


def sample(x, y):
    """The colour at one point, in a 256-unit square."""
    cx = cy = SIZE / 2
    dx, dy = x - cx, y - cy
    r = (dx * dx + dy * dy) ** 0.5

    if r > 124:
        return CLEAR
    if r > 112:
        return NAVY
    if r > 106:
        return CREAM
    if r > 101:
        return NAVY

    # The field, and the marks on it.
    star = _star_points(cx, 104, 30, 13)
    if _inside(star, x, y):
        return NAVY

    # A laurel: two arc bands curving up from the bottom. Arcs rather
    # than the stacked bars this first drew, because at the 6% opacity a
    # watermark is printed at, three solid rectangles read as skeleton
    # placeholders -- as though the card had failed to load -- while a
    # curve reads as part of an emblem.
    if 58 <= r <= 68:
        import math

        deg = math.degrees(math.atan2(dy, dx)) % 360
        if 100 <= deg <= 168 or 12 <= deg <= 80:
            return NAVY

    return CREAM


def build():
    rows = []
    for py in range(SIZE):
        row = bytearray()
        for px in range(SIZE):
            acc = [0, 0, 0, 0]
            for sy in range(SS):
                for sx in range(SS):
                    c = sample(px + (sx + 0.5) / SS, py + (sy + 0.5) / SS)
                    # Premultiply so transparent edges do not fringe dark.
                    a = c[3] / 255
                    acc[0] += c[0] * a
                    acc[1] += c[1] * a
                    acc[2] += c[2] * a
                    acc[3] += c[3]
            n = SS * SS
            a = acc[3] / n
            if a < 1:
                row += bytes((0, 0, 0, 0))
            else:
                scale = 255 / acc[3] * n / n
                del scale
                aa = a / 255
                row += bytes(
                    (
                        min(255, round(acc[0] / n / aa)),
                        min(255, round(acc[1] / n / aa)),
                        min(255, round(acc[2] / n / aa)),
                        round(a),
                    )
                )
        rows.append(row)
    return rows


def png(rows):
    raw = b"".join(b"\x00" + bytes(r) for r in rows)

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


if __name__ == "__main__":
    data = png(build())
    uri = "data:image/png;base64," + base64.b64encode(data).decode()
    print(f"// {len(data)} bytes", flush=True)
    # Wrapped so it can be pasted into Dart as adjacent string literals.
    body = uri
    width = 96
    for i in range(0, len(body), width):
        print(f"'{body[i:i + width]}'")
