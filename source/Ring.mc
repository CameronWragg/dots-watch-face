import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

// The edge ring: 90 dot positions 4 degrees apart, of which six segments of 13
// dots are used. Segment i is centred at i x 60 degrees clockwise from 12 o'clock,
// leaving two empty positions between neighbouring segments.
module Ring {

    const RADIUS = 122;
    const SEGMENTS = 6;
    const DOTS_PER_SEGMENT = 13;
    const DOT_STEP_DEGREES = 4;
    const SEGMENT_STEP_DEGREES = 60;

    const LIT_SIZE = 6;
    const UNLIT_SIZE = 4;
    const UNLIT_COLOUR = 0x555555;

    // Glyphs font characters: lit and unlit dots, and each segment's icon.
    const LIT_DOT = "0";
    const UNLIT_DOT = "4";
    const ICONS = "abcdef";
    const ICON_RADIUS = 100;
    const ICON_SIZE = 16;

    // Battery, heart rate, steps, solar intensity, Body Battery, recovery time.
    const COLOURS = [0x00FF55, 0xFF0055, 0x00AAFF, 0xFFAA00, 0xAA55FF, 0xFFFF00] as Array<Number>;

    // Dot centres as a flat [x0, y0, x1, y1, ...] array: segment by segment, each
    // segment's dots in clockwise order.
    function positions(cx as Number, cy as Number) as Array<Number> {
        var out = new Array<Number>[SEGMENTS * DOTS_PER_SEGMENT * 2];
        var k = 0;
        for (var s = 0; s < SEGMENTS; s++) {
            var first = s * SEGMENT_STEP_DEGREES - (DOTS_PER_SEGMENT - 1) / 2 * DOT_STEP_DEGREES;
            for (var d = 0; d < DOTS_PER_SEGMENT; d++) {
                var a = Math.toRadians(first + d * DOT_STEP_DEGREES);
                out[k] = cx + Math.round(RADIUS * Math.sin(a)).toNumber();
                out[k + 1] = cy - Math.round(RADIUS * Math.cos(a)).toNumber();
                k += 2;
            }
        }
        return out;
    }

    // Top-left corners of the six icons as a flat [x0, y0, ...] array: each icon is
    // centred on its segment, ICON_RADIUS from the centre.
    function iconPositions(cx as Number, cy as Number) as Array<Number> {
        var out = new Array<Number>[SEGMENTS * 2];
        for (var s = 0; s < SEGMENTS; s++) {
            var a = Math.toRadians(s * SEGMENT_STEP_DEGREES);
            out[2 * s] = cx + Math.round(ICON_RADIUS * Math.sin(a)).toNumber() - ICON_SIZE / 2;
            out[2 * s + 1] = cy - Math.round(ICON_RADIUS * Math.cos(a)).toNumber() - ICON_SIZE / 2;
        }
        return out;
    }

    // Draws one segment's dots, lighting them clockwise from its first dot, and its icon.
    function drawSegment(dc as Graphics.Dc, font as Graphics.FontType, dots as Array<Number>, icons as Array<Number>,
            segment as Number, fraction as Float?) as Void {
        var lit = litCount(fraction);
        var colour = COLOURS[segment];
        var k = segment * DOTS_PER_SEGMENT * 2;
        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
        for (var d = 0; d < lit; d++) {
            DotFont.drawGlyphs(dc, font, dots[k] - LIT_SIZE / 2, dots[k + 1] - LIT_SIZE / 2, LIT_DOT);
            k += 2;
        }
        dc.setColor(UNLIT_COLOUR, Graphics.COLOR_TRANSPARENT);
        for (var d = lit; d < DOTS_PER_SEGMENT; d++) {
            DotFont.drawGlyphs(dc, font, dots[k] - UNLIT_SIZE / 2, dots[k + 1] - UNLIT_SIZE / 2, UNLIT_DOT);
            k += 2;
        }
        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
        DotFont.drawGlyphs(dc, font, icons[2 * segment], icons[2 * segment + 1],
            ICONS.substring(segment, segment + 1) as String);
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
