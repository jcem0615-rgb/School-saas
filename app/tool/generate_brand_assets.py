#!/usr/bin/env python3
"""Regenerates the LogicClass brand artwork.

The mark is an L and a C -- a navy letterform on the left, a four-colour
ring on the right -- with a node-and-edge graph laid over them. All of it
is described here rather than drawn by hand, so the light and dark
variants and every launcher icon come from one set of coordinates and
cannot drift apart.

    python3 tool/generate_brand_assets.py            # SVGs only
    python3 tool/generate_brand_assets.py --icons    # SVGs + platform icons

Rasterising needs Chromium via Playwright, since this container has no
SVG tooling; --icons is skipped without it. Run from the app/ directory.
"""
import argparse
import math
import os
import shutil
import struct
import subprocess
import sys

ORANGE, BLUE, CYAN, GREEN = '#F26F1F', '#1A79EA', '#17A2F2', '#40C22F'
PAPER = '#F4F3EE'

# The navy carries the L, and on a dark backdrop the deep original is
# within a few percent of the background -- the letter disappears and the
# nodes read as empty rings. The dark variant lifts it to a tint that
# still reads as the same colour.
NAVY_LIGHT, NAVY_DARK = '#1F3B66', '#8FB2E8'

# What sits behind the crossings so one stroke reads as passing over
# another. Near-white on a pale ground; on a dark one it has to be dark,
# or every edge picks up a glowing outline.
CASING_LIGHT, CASING_DARK = PAPER, '#16233D'

CX, CY, RO, RI = 340.0, 262.0, 168.0, 104.0
SEGMENTS = [(ORANGE, 184, 266), (GREEN, 271, 338), (GREEN, 22, 89), (BLUE, 94, 179)]

A, B, M = (104, 100), (104, 428), (252, 262)
T, R, BO = (452, 120), (452, 262), (452, 404)


def _pt(r, deg):
    a = math.radians(deg)
    return CX + r * math.cos(a), CY + r * math.sin(a)


def _ring_arc(a0, a1):
    large = 1 if (a1 - a0) % 360 > 180 else 0
    x0, y0 = _pt(RO, a0)
    x1, y1 = _pt(RO, a1)
    xi1, yi1 = _pt(RI, a1)
    xi0, yi0 = _pt(RI, a0)
    return (f'M {x0:.2f} {y0:.2f} A {RO} {RO} 0 {large} 1 {x1:.2f} {y1:.2f} '
            f'L {xi1:.2f} {yi1:.2f} A {RI} {RI} 0 {large} 0 {xi0:.2f} {yi0:.2f} Z')


def _offset(p0, p1, d):
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    n = math.hypot(dx, dy)
    return ((p0[0] - dy / n * d, p0[1] + dx / n * d),
            (p1[0] - dy / n * d, p1[1] + dx / n * d))


def logo_svg(navy, casing, background=None):
    """The full mark, letterforms and graph together."""
    o0, o1 = _offset(B, M, -20)
    edges = [
        (navy, A, M, 18),
        (navy, M, B, 18),
        (ORANGE, o0, o1, 13),          # doubles the lower navy stroke
        (ORANGE, A, R, 15),            # the long diagonal across the mark
        (BLUE, T, BO, 14),
        (CYAN, R, (243, 392), 13),
    ]
    nodes = [(A, navy, 40), (B, navy, 40), (M, navy, 45),
             (T, BLUE, 35), (R, CYAN, 42), (BO, BLUE, 35)]

    out = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" '
           'width="512" height="512" role="img" aria-label="LogicClass">']
    if background:
        out.append(f'<rect width="512" height="512" fill="{background}"/>')
    for colour, a0, a1 in SEGMENTS:
        out.append(f'<path d="{_ring_arc(a0, a1)}" fill="{colour}"/>')
    out.append(f'<path d="M 64 98 L 132 98 L 132 396 L 64 396 Z" fill="{navy}"/>')
    out.append(f'<path d="M 64 396 L 246 396 L 246 456 L 64 456 Z" fill="{navy}"/>')
    for _, p0, p1, w in edges:
        out.append(f'<line x1="{p0[0]:.1f}" y1="{p0[1]:.1f}" x2="{p1[0]:.1f}" '
                   f'y2="{p1[1]:.1f}" stroke="{casing}" stroke-width="{w + 7}" '
                   f'stroke-linecap="round"/>')
    for colour, p0, p1, w in edges:
        out.append(f'<line x1="{p0[0]:.1f}" y1="{p0[1]:.1f}" x2="{p1[0]:.1f}" '
                   f'y2="{p1[1]:.1f}" stroke="{colour}" stroke-width="{w}" '
                   f'stroke-linecap="round"/>')
    for (x, y), colour, r in nodes:
        out.append(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{colour}" '
                   f'stroke="{casing}" stroke-width="9"/>')
    out.append('</svg>')
    return '\n'.join(out)


def icon_svg():
    """The launcher icon: the two letters alone.

    The graph turns to mud below about 96px, and a launcher icon is
    routinely drawn at 48. Dropping it is what keeps the L and the C
    readable at the size the icon is actually seen.
    """
    cx, cy, ro, ri = 322.0, 256.0, 150.0, 84.0

    def pt(r, deg):
        a = math.radians(deg)
        return cx + r * math.cos(a), cy + r * math.sin(a)

    def arc(a0, a1):
        large = 1 if (a1 - a0) % 360 > 180 else 0
        x0, y0 = pt(ro, a0)
        x1, y1 = pt(ro, a1)
        xi1, yi1 = pt(ri, a1)
        xi0, yi0 = pt(ri, a0)
        return (f'M {x0:.2f} {y0:.2f} A {ro} {ro} 0 {large} 1 {x1:.2f} {y1:.2f} '
                f'L {xi1:.2f} {yi1:.2f} A {ri} {ri} 0 {large} 0 {xi0:.2f} {yi0:.2f} Z')

    out = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" '
           'width="512" height="512" role="img" aria-label="LogicClass">',
           f'<rect width="512" height="512" fill="{PAPER}"/>']
    for colour, a0, a1 in SEGMENTS:
        out.append(f'<path d="{arc(a0, a1)}" fill="{colour}"/>')
    out.append(f'<path d="M 96 106 L 168 106 L 168 344 L 96 344 Z" fill="{NAVY_LIGHT}"/>')
    out.append(f'<path d="M 96 344 L 258 344 L 258 406 L 96 406 Z" fill="{NAVY_LIGHT}"/>')
    out.append('</svg>')
    return '\n'.join(out)


def logicgrid_svg():
    """PLACEHOLDER for LogicGrid's own mark.

    Drawn here because their artwork was not available. Replace this file
    with the real logo -- same name, same 64x64 viewBox -- and every use
    of it in the app updates with no code change.
    """
    out = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" '
           'width="64" height="64" role="img" aria-label="LogicGrid">']
    xs = [14, 32, 50]
    for x in xs:
        out.append(f'<line x1="{x}" y1="14" x2="{x}" y2="50" stroke="{NAVY_LIGHT}" '
                   f'stroke-width="3.2" stroke-linecap="round" opacity="0.55"/>')
        out.append(f'<line x1="14" y1="{x}" x2="50" y2="{x}" stroke="{NAVY_LIGHT}" '
                   f'stroke-width="3.2" stroke-linecap="round" opacity="0.55"/>')
    for yi, y in enumerate(xs):
        for xi, x in enumerate(xs):
            centre = xi == 1 and yi == 1
            colour = CYAN if centre else (BLUE if (xi != 1 and yi != 1) else NAVY_LIGHT)
            out.append(f'<circle cx="{x}" cy="{y}" r="{6.5 if centre else 5}" fill="{colour}"/>')
    out.append('</svg>')
    return '\n'.join(out)


def write_svgs():
    os.makedirs('assets/brand', exist_ok=True)
    files = {
        # No background on the in-app marks: they sit on glass panes, and a
        # ground would show as a pale square.
        'assets/brand/logicclass-logo.svg': logo_svg(NAVY_LIGHT, CASING_LIGHT),
        'assets/brand/logicclass-logo-dark.svg': logo_svg(NAVY_DARK, CASING_DARK),
        'assets/brand/logicclass-icon.svg': icon_svg(),
        'assets/brand/logicgrid-logo.svg': logicgrid_svg(),
    }
    for path, body in files.items():
        open(path, 'w').write(body)
        print('wrote', path)


ICON_SIZES = [16, 20, 29, 32, 40, 48, 58, 60, 64, 72, 76, 80, 87, 96,
              120, 128, 144, 152, 167, 180, 192, 256, 512, 1024]


def write_icons(rasterizer, workdir):
    os.makedirs(workdir, exist_ok=True)
    for n in ICON_SIZES:
        out = os.path.join(workdir, f'{n}.png')
        if not os.path.exists(out):
            subprocess.run(['node', rasterizer,
                            os.path.abspath('assets/brand/logicclass-icon.svg'),
                            out, str(n)], check=True)

    def src(n):
        return os.path.join(workdir, f'{n}.png')

    for density, n in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96),
                       ('xxhdpi', 144), ('xxxhdpi', 192)]:
        dst = f'android/app/src/main/res/mipmap-{density}/ic_launcher.png'
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy(src(n), dst)

    shutil.copy(src(32), 'web/favicon.png')
    for name, n in [('Icon-192', 192), ('Icon-512', 512),
                    ('Icon-maskable-192', 192), ('Icon-maskable-512', 512)]:
        shutil.copy(src(n), f'web/icons/{name}.png')

    ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    if os.path.isdir(ios):
        for f in os.listdir(ios):
            if not f.endswith('.png'):
                continue
            dims, _, scale = f[:-4].partition('@')
            # 83.5x83.5@2x is a real iPad size; the sides are not all integers.
            side = float(dims.split('-')[-1].split('x')[0])
            px = round(side * int((scale or '1x').rstrip('x')))
            if os.path.exists(src(px)):
                shutil.copy(src(px), os.path.join(ios, f))

    write_ico([16, 32, 48, 64, 128, 256], workdir,
              'windows/runner/resources/app_icon.ico')
    print('icons written')


def write_ico(sizes, workdir, out):
    """Assembles a .ico by hand.

    An .ico is a small directory of images, and Vista onwards accepts PNG
    frames verbatim -- which is the only reason this is possible here,
    with no image library installed.
    """
    frames = [(n, open(os.path.join(workdir, f'{n}.png'), 'rb').read()) for n in sizes]
    header = struct.pack('<HHH', 0, 1, len(frames))
    offset = len(header) + 16 * len(frames)
    entries, blobs = b'', b''
    for n, data in frames:
        side = 0 if n == 256 else n          # 0 means 256
        entries += struct.pack('<BBBBHHII', side, side, 0, 0, 1, 32, len(data), offset)
        blobs += data
        offset += len(data)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    open(out, 'wb').write(header + entries + blobs)


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--icons', action='store_true',
                    help='also rasterise the platform launcher icons')
    ap.add_argument('--rasterizer', default=os.environ.get('RASTERIZER', ''),
                    help='node script taking svg, out.png, size')
    ap.add_argument('--workdir', default='/tmp/logicclass-icons')
    args = ap.parse_args()

    if not os.path.isdir('assets'):
        sys.exit('run this from the app/ directory')
    write_svgs()
    if args.icons:
        if not args.rasterizer or not os.path.exists(args.rasterizer):
            sys.exit('--icons needs --rasterizer pointing at the Chromium script')
        write_icons(args.rasterizer, args.workdir)
