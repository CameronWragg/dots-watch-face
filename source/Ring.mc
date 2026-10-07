import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

// The edge ring: 90 dot positions 4 degrees apart, of which six segments of 13
// dots are used. Segment i is centred at i x 60 degrees clockwise from 12 o'clock,
// leaving two empty positions between neighbouring segments.
module Ring {

    // Must match RADIUS in tools/make_ring.py, which places the dots.
    const RADIUS = 122;
    const SEGMENTS = 6;
    const DOTS_PER_SEGMENT = 13;
    const SEGMENT_STEP_DEGREES = 60;

    const LIT_SIZE = 6;
    const UNLIT_SIZE = 4;
    const UNLIT_COLOUR = 0x555555;

    const ICON_RADIUS = 100;

    // Battery, heart rate, steps, solar intensity, Body Battery, recovery time.
    const COLOURS = [0x00FF55, 0xFF0055, 0x00AAFF, 0xFFAA00, 0xAA55FF, 0xFFFF00] as Array<Number>;

    // Dot centres as a flat [x0, y0, x1, y1, ...] array: segment by segment, each
    // segment's dots in clockwise order. The whole-pixel positions come from
    // tools/make_ring.py, which spaces them evenly on the circle.
    function positions(cx as Number, cy as Number) as Array<Number> {
        var offsets = RingOffsets.OFFSETS;
        var out = new Array<Number>[offsets.size()];
        for (var i = 0; i < offsets.size(); i += 2) {
            out[i] = cx + offsets[i];
            out[i + 1] = cy - offsets[i + 1];
        }
        return out;
    }

    // Top-left corners of the six icons as a flat [x0, y0, ...] array: each icon is
    // centred on its segment, ICON_RADIUS from the centre.
    function iconPositions(cx as Number, cy as Number) as Array<Number> {
        var out = new Array<Number>[SEGMENTS * 2];
        for (var s = 0; s < SEGMENTS; s++) {
            var a = Math.toRadians(s * SEGMENT_STEP_DEGREES);
            out[2 * s] = cx + Math.round(ICON_RADIUS * Math.sin(a)).toNumber() - Icons.SIZE / 2;
            out[2 * s + 1] = cy - Math.round(ICON_RADIUS * Math.cos(a)).toNumber() - Icons.SIZE / 2;
        }
        return out;
    }

    // Brings a segment from `from` lit dots to `to`, redrawing only the dots whose
    // state changes. A `from` of -1 means nothing is drawn yet: all 13 dots and the
    // segment's icon (Icons number `segment`) are drawn onto a black background.
    function drawSegment(dc as Graphics.Dc, dots as Array<Number>, icons as Array<Number>, segment as Number,
            from as Number, to as Number) as Void {
        var colour = COLOURS[segment];
        var first = segment * DOTS_PER_SEGMENT * 2;
        var start = from < 0 ? 0 : (from < to ? from : to);
        var end = from < 0 ? DOTS_PER_SEGMENT : (from < to ? to : from);

        // Dots turning on: a lit dot covers an unlit one completely.
        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
        for (var d = start; d < to && d < end; d++) {
            var k = first + 2 * d;
            DotFont.drawDot(dc, dots[k] - LIT_SIZE / 2, dots[k + 1] - LIT_SIZE / 2, LIT_SIZE);
        }

        // Dots turning off: clear the lit dot first, unless nothing was drawn yet.
        var offStart = start > to ? start : to;
        if (from >= 0 && offStart < end) {
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            for (var d = offStart; d < end; d++) {
                var k = first + 2 * d;
                dc.fillRectangle(dots[k] - LIT_SIZE / 2, dots[k + 1] - LIT_SIZE / 2, LIT_SIZE, LIT_SIZE);
            }
        }
        dc.setColor(UNLIT_COLOUR, Graphics.COLOR_TRANSPARENT);
        for (var d = offStart; d < end; d++) {
            var k = first + 2 * d;
            DotFont.drawDot(dc, dots[k] - UNLIT_SIZE / 2, dots[k + 1] - UNLIT_SIZE / 2, UNLIT_SIZE);
        }

        if (from < 0) {
            dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
            Icons.draw(dc, segment, icons[2 * segment], icons[2 * segment + 1]);
        }
    }

    // Lit dots for a fraction, rounded and clamped to 0..13. A missing value lights none.
    function litCount(fraction as Float?) as Number {
        if (fraction == null) {
            return 0;
        }
        var n = Math.round(fraction * DOTS_PER_SEGMENT).toNumber();
        return n < 0 ? 0 : (n > DOTS_PER_SEGMENT ? DOTS_PER_SEGMENT : n);
    }
}
