#!/usr/bin/env python3
"""Generate source/Icons.mc: the face's 16 x 16 icons as lists of rectangles.

Each icon is drawn with dc.fillRectangle in the current colour, so setColor tints
it and every pixel lands exactly where it is placed, with no font metrics involved.

    python3 tools/make_icons.py                      # writes source/Icons.mc
    python3 tools/make_icons.py --preview out.png    # also an 8x preview sheet

Icons are described as signed distance functions on a 16 x 16 grid, stroked,
supersampled and thresholded to 1 bit, since the display has no alpha blending.
"""
import math
import os
import struct
import sys
import zlib

ICON = 16
STATUS_ICON = 10
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


def polyline(pts):
    """Unsigned distance to an open path through pts."""
    return lambda x, y: min(_seg_dist(x, y, *pts[i], *pts[i + 1]) for i in range(len(pts) - 1))


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
    # Ring data points
    'BATTERY': union(stroke(rbox(1.0, 4.0, 11.0, 12.0, 1.0)), rbox(13.0, 6.0, 15.0, 10.0, 0.1)),  # battery
    'HEART': stroke(union(circle(5.3, 6.2, 3.3), circle(10.7, 6.2, 3.3),
                      polygon([(2.25, 7.6), (8, 13.9), (13.75, 7.6), (8, 6)]))),  # heart rate
    'FOOTPRINTS': union(stroke(ellipse(4.6, 5.6, 2.3, 3.7)), stroke(ellipse(11.4, 10.4, 2.3, 3.7))),  # steps
    'SUN': sun_shape(),  # sun (solar intensity, and clear weather)
    'BOLT': bolt(),  # Body Battery
    'GAUGE': union(line(arc(8, 11.5, 6.3, 270, 90)), capsule(8, 11.5, 10.8, 7.3, STROKE / 2)),  # recovery time
    'STRESS': line(polyline([(1, 9), (4, 9), (6, 3.5), (9.5, 13), (11.5, 7), (13, 9), (15, 9)])),  # stress
    'STAIRS': line(polyline([(1.5, 14), (1.5, 11), (5.5, 11), (5.5, 7), (9.5, 7), (9.5, 3), (14.5, 3)])),  # floors climbed
    'STOPWATCH': union(stroke(circle(8, 9.5, 5.3)), capsule(8, 1.5, 8, 2.8, STROKE / 2),
                       capsule(8, 9.5, 10.3, 7.2, STROKE / 2)),  # intensity minutes
    'DROP': stroke(union(circle(8, 10.3, 4.2), polygon([(8, 1.5), (4.1, 9), (11.9, 9)]))),  # pulse ox
    'MOON': minus(circle(7.5, 8.5, 6.2), circle(11.2, 5.8, 5.2)),  # sleep score
    'SUNRISE': union(capsule(1, 13.5, 15, 13.5, STROKE / 2), minus(circle(8, 13.5, 4.2), lambda x, y: 13.5 - y),
                     *[capsule(8 + 6.2 * math.sin(math.radians(a)), 13.5 - 6.2 * math.cos(math.radians(a)),
                               8 + 8.2 * math.sin(math.radians(a)), 13.5 - 8.2 * math.cos(math.radians(a)), STROKE / 2)
                       for a in (-50, 0, 50)]),  # daylight left (offered as Sunset)
    # Weather conditions
    'PARTLY_CLOUDY': union(minus(partial_sun(), lambda x, y: translate(scale(cloud_fill(), 0.75), 2.4, 2.2)(x, y) - 1.3),
               translate(scale(cloud(), 0.75), 2.4, 2.2)),  # partly cloudy
    'CLOUDY': cloud(),  # cloudy
    'RAIN': union(small_cloud(), *[capsule(x, y, x, y + 2, 0.6) for x, y in ((5.5, 12), (8.5, 13), (11.5, 12))]),  # rain
    'SNOW': union(small_cloud(), *[rbox(x - 1, y - 1, x + 1, y + 1, 0.1) for x, y in ((5, 13), (8, 15), (11, 13))]),  # snow
    'THUNDERSTORM': union(minus(small_cloud(), lambda x, y: zigzag(x, y) - 1.6), line(zigzag, 1.2)),  # thunderstorm
    'FOG': union(capsule(2, 5, 14, 5, STROKE / 2), capsule(4, 8.5, 12, 8.5, STROKE / 2),
               capsule(2, 12, 14, 12, STROKE / 2)),  # fog
}

# Status indicators on a 10 x 10 grid, shown below the weather while they apply.
STATUS_ICONS = {
    'NOTIFICATIONS': union(polygon([(5, 0.4), (7.2, 1.8), (7.6, 6.2), (9.6, 7.9), (0.4, 7.9), (2.4, 6.2), (2.8, 1.8)]),
                           rbox(4, 8.6, 6, 9.8, 0.3)),  # bell
    'PHONE_DISCONNECTED': union(minus(stroke(rbox(2.2, 0.6, 7.8, 9.4, 1.2), 1.1),
                                      capsule(0.6, 0.6, 9.4, 9.4, 1.4)),
                                capsule(0.6, 0.6, 9.4, 9.4, 0.55)),  # phone, struck through
    'ALARM': union(stroke(circle(5, 5.6, 3.6), 1.2), capsule(5, 5.6, 5, 3.6, 0.55), capsule(5, 5.6, 6.4, 5.6, 0.55),
                   capsule(0.8, 2.2, 2.2, 0.8, 0.7), capsule(9.2, 2.2, 7.8, 0.8, 0.7)),  # alarm clock
    'DO_NOT_DISTURB': minus(circle(5, 5, 4.6), rbox(2, 4.2, 8, 5.8, 0.1)),  # no-entry sign
}


def rasterise(f, size=ICON):
    rows = []
    n = SUPERSAMPLE
    for py in range(size):
        row = ''
        for px in range(size):
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


def rectangles(rows):
    """Covers an icon's pixels with rectangles: runs of pixels in a row, each merged
    with identical runs directly below it."""
    done, open_, rects = [], {}, []
    size = len(rows)
    for y, row in enumerate(rows + ['.' * size]):
        runs, x = [], 0
        while x < size:
            if row[x] == '#':
                w = 1
                while x + w < size and row[x + w] == '#':
                    w += 1
                runs.append((x, w))
                x += w
            else:
                x += 1
        still_open = {}
        for run in runs:
            if run in open_:
                still_open[run] = open_.pop(run)
            else:
                still_open[run] = y
        for (x, w), top in open_.items():
            rects.append((x, top, w, y - top))
        open_ = still_open
    return sorted(rects, key=lambda r: (r[1], r[0]))


TEMPLATE = """// Generated by tools/make_icons.py: edit the icons there, then regenerate.
import Toybox.Graphics;
import Toybox.Lang;

// The face's 16 x 16 icons, each a list of rectangles filled in the current colour.
module Icons {{

    const SIZE = {size};

    const STATUS_SIZE = {status_size};

    // Ring data points, weather conditions, then status indicators.
{names}
    const COUNT = {count};

    // Start of each icon's rectangles in RECTS, then the end of the last icon's.
    const STARTS = [{starts}] as Array<Number>;

    // One rectangle per entry: x | y << 4 | (width - 1) << 8 | (height - 1) << 12.
    const RECTS = [
{rects}
    ] as Array<Number>;

    // Draws an icon in the current colour with its top-left pixel at (left, top).
    function draw(dc as Graphics.Dc, icon as Number, left as Number, top as Number) as Void {{
        for (var i = STARTS[icon]; i < STARTS[icon + 1]; i++) {{
            var r = RECTS[i];
            dc.fillRectangle(left + (r & 15), top + (r >> 4 & 15), (r >> 8 & 15) + 1, (r >> 12) + 1);
        }}
    }}
}}
"""


def main():
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
    icons = [(c, rasterise(f)) for c, f in ICONS.items()]
    icons += [(c, rasterise(f, STATUS_ICON)) for c, f in STATUS_ICONS.items()]

    names, starts, lines, n = [], [], [], 0
    for i, (c, rows) in enumerate(icons):
        rects = rectangles(rows)
        names.append('    const %s = %d;' % (c, i))
        starts.append(n)
        packed = ['0x%04x' % (x | y << 4 | (w - 1) << 8 | (h - 1) << 12) for x, y, w, h in rects]
        for k in range(0, len(packed), 10):
            lines.append('        ' + ', '.join(packed[k:k + 10]) + ',' + ('  // ' + c.lower() if k == 0 else ''))
        n += len(rects)
    starts.append(n)

    with open(os.path.join(root, 'source', 'Icons.mc'), 'w') as f:
        f.write(TEMPLATE.format(size=ICON, status_size=STATUS_ICON, count=len(icons), names='\n'.join(names), starts=', '.join(map(str, starts)),
                                rects='\n'.join(lines)))

    if '--preview' in sys.argv:
        # 8x sheet of the icons, grey grid lines between pixels.
        s, cell = 8, ICON * 8 + 8
        pw, ph = cell * len(icons), cell
        rows = [[40] * (pw * 4) for _ in range(ph)]
        for i, (c, rr) in enumerate(icons):
            for py in range(ICON * s):
                for px in range(ICON * s):
                    on = py // s < len(rr) and px // s < len(rr) and rr[py // s][px // s] == '#'
                    v = 255 if on else (60 if (px % s == 0 or py % s == 0) else 0)
                    o = (i * cell + px) * 4
                    rows[py][o:o + 4] = [v, v, v, 255]
        write_png(sys.argv[sys.argv.index('--preview') + 1], pw, ph, rows)


if __name__ == '__main__':
    main()
