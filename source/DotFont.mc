import Toybox.Graphics;
import Toybox.Lang;

// The dot-matrix font shared by the time, date and weather. Every glyph is 7 rows
// tall; only the dot size and pitch change between uses. Glyphs are separated by
// one empty column.
module DotFont {

    const ROWS = 7;

    // Characters with a glyph, in table order.
    const CHARS = "0123456789CTUE:° ADFHIMNORSW-_%";

    // Glyph widths in columns, in CHARS order.
    const WIDTHS = [5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 1, 2, 2,
        5, 5, 5, 5, 3, 5, 5, 5, 5, 5, 5, 3, 5, 5] as Array<Number>;

    // 7 rows per glyph, in CHARS order. Each row is a bit mask with the leftmost
    // column in the highest of the glyph's width bits.
    const GLYPHS = [
        0x0e, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0e, // 0
        0x04, 0x0c, 0x04, 0x04, 0x04, 0x04, 0x0e, // 1
        0x0e, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1f, // 2
        0x1e, 0x01, 0x01, 0x0e, 0x01, 0x01, 0x1e, // 3
        0x02, 0x06, 0x0a, 0x12, 0x1f, 0x02, 0x02, // 4
        0x1f, 0x10, 0x1e, 0x01, 0x01, 0x11, 0x0e, // 5
        0x06, 0x08, 0x10, 0x1e, 0x11, 0x11, 0x0e, // 6
        0x1f, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08, // 7
        0x0e, 0x11, 0x11, 0x0e, 0x11, 0x11, 0x0e, // 8
        0x0e, 0x11, 0x11, 0x0f, 0x01, 0x02, 0x0c, // 9
        0x0e, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0e, // C
        0x1f, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04, // T
        0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0e, // U
        0x1f, 0x10, 0x10, 0x1e, 0x10, 0x10, 0x1f, // E
        0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, // :
        0x03, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, // degree
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // space
        0x0e, 0x11, 0x11, 0x1f, 0x11, 0x11, 0x11, // A
        0x1e, 0x11, 0x11, 0x11, 0x11, 0x11, 0x1e, // D
        0x1f, 0x10, 0x10, 0x1e, 0x10, 0x10, 0x10, // F
        0x11, 0x11, 0x11, 0x1f, 0x11, 0x11, 0x11, // H
        0x07, 0x02, 0x02, 0x02, 0x02, 0x02, 0x07, // I
        0x11, 0x1b, 0x15, 0x15, 0x11, 0x11, 0x11, // M
        0x11, 0x11, 0x19, 0x15, 0x13, 0x11, 0x11, // N
        0x0e, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0e, // O
        0x1e, 0x11, 0x11, 0x1e, 0x14, 0x12, 0x11, // R
        0x0f, 0x10, 0x10, 0x0e, 0x01, 0x01, 0x1e, // S
        0x11, 0x11, 0x11, 0x15, 0x15, 0x15, 0x0a, // W
        0x00, 0x00, 0x00, 0x07, 0x00, 0x00, 0x00, // minus
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // blank digit cell, for 12 hour times before 10
        0x18, 0x19, 0x02, 0x04, 0x08, 0x13, 0x03, // percent
    ] as Array<Number>;

    const LARGE_SIZE = 6;
    const LARGE_PITCH = 8;
    const SMALL_SIZE = 3;
    const SMALL_PITCH = 4;

    // Fills one round dot of 6, 4 or 3 px in the current colour, with its bounding
    // box's top-left pixel at (x, y). The 6 and 4 px dots are squares with their
    // corner pixels left off; at 3 px a full square reads as round.
    function drawDot(dc as Graphics.Dc, x as Number, y as Number, size as Number) as Void {
        if (size == SMALL_SIZE) {
            dc.fillRectangle(x, y, size, size);
        } else {
            dc.fillRectangle(x + 1, y, size - 2, size);
            dc.fillRectangle(x, y + 1, size, size - 2);
        }
    }

    // Index of a character in the tables, or null when it has no glyph.
    function indexOf(c as Char) as Number? {
        return CHARS.find(c.toString());
    }

    // Width in columns of a string, including the gaps between glyphs.
    function columns(text as String) as Number {
        var chars = text.toCharArray();
        var total = 0;
        for (var i = 0; i < chars.size(); i++) {
            var g = indexOf(chars[i]);
            if (g != null) {
                total += WIDTHS[g] + 1;
            }
        }
        return total > 0 ? total - 1 : 0;
    }

    // Width in pixels of a string drawn with large (6 px) or small (3 px) dots.
    function width(text as String, large as Boolean) as Number {
        var cols = columns(text);
        if (cols == 0) {
            return 0;
        }
        return large ? (cols - 1) * LARGE_PITCH + LARGE_SIZE : (cols - 1) * SMALL_PITCH + SMALL_SIZE;
    }

    // Height in pixels of text drawn with large or small dots.
    function height(large as Boolean) as Number {
        return large ? (ROWS - 1) * LARGE_PITCH + LARGE_SIZE : (ROWS - 1) * SMALL_PITCH + SMALL_SIZE;
    }

    // Draws a string in the current colour with its top-left dot at (left, top).
    function draw(dc as Graphics.Dc, text as String, left as Number, top as Number, large as Boolean) as Void {
        var chars = text.toCharArray();
        var x = left;
        for (var i = 0; i < chars.size(); i++) {
            var g = indexOf(chars[i]);
            if (g != null) {
                drawGlyph(dc, g, x, top, large);
                x += (WIDTHS[g] + 1) * (large ? LARGE_PITCH : SMALL_PITCH);
            }
        }
    }

    // Changes `old`, already drawn at (left, top), into `text` by clearing and
    // redrawing only the glyphs that differ. Both strings must have the same
    // glyph widths in the same order, so every glyph keeps its place.
    function redrawChanged(dc as Graphics.Dc, old as String, text as String, left as Number, top as Number,
            large as Boolean, colour as Number) as Void {
        var was = old.toCharArray();
        var now = text.toCharArray();
        var pitch = large ? LARGE_PITCH : SMALL_PITCH;
        var x = left;
        for (var i = 0; i < now.size(); i++) {
            var g = indexOf(now[i]);
            if (g == null) {
                continue;
            }
            if (now[i] != was[i]) {
                var cols = WIDTHS[g];
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(x, top, (cols - 1) * pitch + (large ? LARGE_SIZE : SMALL_SIZE), height(large));
                dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
                drawGlyph(dc, g, x, top, large);
            }
            x += (WIDTHS[g] + 1) * pitch;
        }
    }

    // Draws glyph number g in the current colour with its top-left dot at (left, top).
    function drawGlyph(dc as Graphics.Dc, g as Number, left as Number, top as Number, large as Boolean) as Void {
        var size = large ? LARGE_SIZE : SMALL_SIZE;
        var pitch = large ? LARGE_PITCH : SMALL_PITCH;
        var width = WIDTHS[g];
        for (var r = 0; r < ROWS; r++) {
            var bits = GLYPHS[g * ROWS + r];
            for (var k = 0; k < width; k++) {
                if ((bits >> (width - 1 - k)) & 1 == 1) {
                    drawDot(dc, left + k * pitch, top + r * pitch, size);
                }
            }
        }
    }
}
