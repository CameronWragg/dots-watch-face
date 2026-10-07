#!/usr/bin/env python3
"""Generate the Glyphs font: the face's dots and 16 x 16 icons as one BMFont.

Connect IQ tints custom font glyphs with the current foreground colour, so every
dot and icon can be drawn in any segment colour with drawText.

    python3 tools/make_glyphs.py            # writes resources/fonts/glyphs.{fnt,png}
    python3 tools/make_glyphs.py --preview out.png   # also an 8x preview sheet

Icons are described as signed distance functions on a 16 x 16 grid, stroked,
supersampled and thresholded to 1 bit, since the display has no alpha blending.
"""
import math
import os
import struct
import sys
import zlib

ICON = 16
STROKE = 1.6
SUPERSAMPLE = 4
THRESHOLD = 0.5

# ---------------------------------------------------------------------------
# Signed distance helpers (negative inside). Coordinates: x right, y down.


def circle(cx, cy, r):
    return lambda x, y: math.hypot(x - cx, y - cy) - r


def ellipse(cx, cy, rx, ry):
    k = min(rx, ry)
    return lambda x, y: (math.hypot((x - cx) / rx, (y - cy) / ry) - 1) * k


def rbox(x0, y0, x1, y1, r):
    cx, cy, hx, hy = (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2 - r, (y1 - y0) / 2 - r

    def f(x, y):
        qx, qy = abs(x - cx) - hx, abs(y - cy) - hy
        return math.hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - r
    return f


def _seg_dist(x, y, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(x - ax - t * dx, y - ay - t * dy)


def capsule(ax, ay, bx, by, r):
    return lambda x, y: _seg_dist(x, y, ax, ay, bx, by) - r


def polygon(pts):
    def f(x, y):
        d = min(_seg_dist(x, y, *pts[i], *pts[(i + 1) % len(pts)]) for i in range(len(pts)))
        inside = False
        for i in range(len(pts)):
            (ax, ay), (bx, by) = pts[i], pts[(i + 1) % len(pts)]
            if (ay > y) != (by > y) and x < ax + (y - ay) * (bx - ax) / (by - ay):
                inside = not inside
        return -d if inside else d
    return f


def arc(cx, cy, r, a0, a1):
    """Arc of radius r from angle a0 to a1 degrees, clockwise from 12 o'clock."""
    def point(a):
        t = math.radians(a)
        return cx + r * math.sin(t), cy - r * math.cos(t)
    (sx, sy), (ex, ey) = point(a0), point(a1)

    def f(x, y):
        a = math.degrees(math.atan2(x - cx, -(y - cy))) % 360
        if (a - a0) % 360 <= (a1 - a0) % 360:
            return abs(math.hypot(x - cx, y - cy) - r)
        return min(math.hypot(x - sx, y - sy), math.hypot(x - ex, y - ey))
    return f


def union(*fs):
    return lambda x, y: min(f(x, y) for f in fs)


def minus(f, g):
    return lambda x, y: max(f(x, y), -g(x, y))


def stroke(f, w=STROKE):
    return lambda x, y: abs(f(x, y)) - w / 2


def line(f, w=STROKE):
    """Stroke an unsigned distance (arcs, open paths)."""
    return lambda x, y: f(x, y) - w / 2


def translate(f, dx, dy):
    return lambda x, y: f(x - dx, y - dy)


def scale(f, s, ox=8, oy=8):
    return lambda x, y: f(ox + (x - ox) / s, oy + (y - oy) / s) * s


# ---------------------------------------------------------------------------
# Icons


def sun_shape(cx=8, cy=8, core=2.7, ray_in=4.9, ray_out=6.6):
    rays = [capsule(cx + ray_in * math.sin(t), cy - ray_in * math.cos(t),
                    cx + ray_out * math.sin(t), cy - ray_out * math.cos(t), STROKE / 2)
            for t in (math.radians(a) for a in range(0, 360, 45))]
    return union(stroke(circle(cx, cy, core)), *rays)


def cloud_fill():
    return union(rbox(1.2, 8.2, 14.8, 13.6, 2.7), circle(6.6, 7.6, 3.6), circle(10.7, 8.6, 2.7))


def cloud():
    return stroke(cloud_fill())


def small_cloud():
    """Cloud lifted to the top 10 rows, leaving room for weather beneath it."""
    return translate(scale(cloud(), 0.85, 8, 8), 0, -3.2)


BOLT = [(13, 2), (3, 14), (12, 14), (11, 22), (21, 10), (12, 10)]  # 24-grid lightning bolt


def bolt(s=16 / 24, dx=0.0, dy=0.0):
    return stroke(polygon([(x * s + dx, y * s + dy) for x, y in BOLT]))


def partial_sun():
    """A sun in the top-left corner, for partly cloudy; the cloud covers its lower right."""
    cx, cy = 6.0, 6.0
    rays = [capsule(cx + 4.4 * math.sin(t), cy - 4.4 * math.cos(t),
                    cx + 5.4 * math.sin(t), cy - 5.4 * math.cos(t), STROKE / 2)
            for t in (math.radians(a) for a in (270, 315, 0))]
    return union(stroke(circle(cx, cy, 2.6)), *rays)


def zigzag(x, y):
    """Lightning under a small cloud."""
    pts = [(10.0, 9.5), (7.0, 12.5), (9.5, 12.5), (7.0, 15.5)]
    return min(_seg_dist(x, y, *pts[i], *pts[i + 1]) for i in range(len(pts) - 1))


ICONS = {
    # Ring segments, in segment order
    'a': union(stroke(rbox(1.0, 4.0, 11.0, 12.0, 1.0)), rbox(13.0, 6.0, 15.0, 10.0, 0.1)),  # battery
    'b': stroke(union(circle(5.3, 6.2, 3.3), circle(10.7, 6.2, 3.3),
                      polygon([(2.25, 7.6), (8, 13.9), (13.75, 7.6), (8, 6)]))),  # heart
    'c': union(stroke(ellipse(4.6, 5.6, 2.3, 3.7)), stroke(ellipse(11.4, 10.4, 2.3, 3.7))),  # footprints
    'd': sun_shape(),  # sun (solar intensity, and clear weather)
    'e': bolt(),  # Body Battery
    'f': union(line(arc(8, 11.5, 6.3, 270, 90)), capsule(8, 11.5, 10.8, 7.3, STROKE / 2)),  # gauge
    # Weather conditions
    'g': union(minus(partial_sun(), lambda x, y: translate(scale(cloud_fill(), 0.75), 2.4, 2.2)(x, y) - 1.3),
               translate(scale(cloud(), 0.75), 2.4, 2.2)),  # partly cloudy
    'h': cloud(),  # cloudy
    'i': union(small_cloud(), *[capsule(x, y, x, y + 2, 0.6) for x, y in ((5.5, 12), (8.5, 13), (11.5, 12))]),  # rain
    'j': union(small_cloud(), *[rbox(x - 1, y - 1, x + 1, y + 1, 0.1) for x, y in ((5, 13), (8, 15), (11, 13))]),  # snow
    'k': union(minus(small_cloud(), lambda x, y: zigzag(x, y) - 1.6), line(zigzag, 1.2)),  # thunderstorm
    'l': union(capsule(2, 5, 14, 5, STROKE / 2), capsule(4, 8.5, 12, 8.5, STROKE / 2),
               capsule(2, 12, 14, 12, STROKE / 2)),  # fog
}

# Dots, drawn exactly rather than from distance functions.
DOTS = {
    '0': ['.####.', '######', '######', '######', '######', '.####.'],  # 6 px: ring lit, time
    '2': ['###', '###', '###'],  # 3 px: date and weather
    '4': ['.##.', '####', '####', '.##.'],  # 4 px: ring unlit
}
# Characters that only advance: empty cells in a row of dots.
ADVANCE = {'0': 8, '1': 8, '2': 4, '3': 4, '4': 4}


def rasterise(f):
    rows = []
    n = SUPERSAMPLE
    for py in range(ICON):
        row = ''
        for px in range(ICON):
            hits = sum(f(px + (i + 0.5) / n, py + (j + 0.5) / n) <= 0 for i in range(n) for j in range(n))
            row += '#' if hits / (n * n) >= THRESHOLD else '.'
        rows.append(row)
    return rows


# ---------------------------------------------------------------------------
# Output


def write_png(path, width, height, rgba_rows):
    raw = b''.join(b'\0' + bytes(r) for r in rgba_rows)

    def chunk(kind, data):
        c = kind + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b'')
    with open(path, 'wb') as f:
        f.write(png)


def main():
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
    out = os.path.join(root, 'resources', 'fonts')

    glyphs = []  # (char, rows, xadvance)
    for c, rows in DOTS.items():
        glyphs.append((c, rows, ADVANCE[c]))
    for c in ('1', '3'):
        glyphs.append((c, ['.'], ADVANCE[c]))
    for c, f in ICONS.items():
        glyphs.append((c, rasterise(f), ICON))

    # Pack left to right with a 1 px gap.
    width = sum(len(g[1][0]) + 1 for g in glyphs)
    height = ICON
    pixels = [[0] * (width * 4) for _ in range(height)]
    chars = []
    x = 0
    for c, rows, adv in sorted(glyphs, key=lambda g: g[0]):
        w, h = len(rows[0]), len(rows)
        for yy, row in enumerate(rows):
            for xx, p in enumerate(row):
                if p == '#':
                    pixels[yy][(x + xx) * 4:(x + xx) * 4 + 4] = [255, 255, 255, 255]
        chars.append('char id=%-4d x=%-4d y=0 width=%-3d height=%-3d xoffset=0 yoffset=0 xadvance=%-3d page=0 chnl=15'
                     % (ord(c), x, w, h, adv))
        x += w + 1

    write_png(os.path.join(out, 'glyphs.png'), width, height, pixels)
    fnt = ['info face="Glyphs" size=%d bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=0 aa=1 '
           'padding=0,0,0,0 spacing=1,1 outline=0' % ICON,
           'common lineHeight=%d base=%d scaleW=%d scaleH=%d pages=1 packed=0 alphaChnl=1 redChnl=0 '
           'greenChnl=0 blueChnl=0' % (ICON, ICON, width, height),
           'page id=0 file="glyphs.png"',
           'chars count=%d' % len(chars)] + chars
    with open(os.path.join(out, 'glyphs.fnt'), 'w') as f:
        f.write('\n'.join(fnt) + '\n')

    if '--preview' in sys.argv:
        # 8x sheet of the icons, grey grid lines between pixels.
        icons = [g for g in sorted(glyphs) if g[0] in ICONS]
        s, cell = 8, ICON * 8 + 8
        pw, ph = cell * len(icons), cell
        rows = [[40] * (pw * 4) for _ in range(ph)]
        for i, (c, rr, _) in enumerate(icons):
            for py in range(ICON * s):
                for px in range(ICON * s):
                    on = rr[py // s][px // s] == '#'
                    v = 255 if on else (60 if (px % s == 0 or py % s == 0) else 0)
                    o = (i * cell + px) * 4
                    rows[py][o:o + 4] = [v, v, v, 255]
        write_png(sys.argv[sys.argv.index('--preview') + 1], pw, ph, rows)


if __name__ == '__main__':
    main()
