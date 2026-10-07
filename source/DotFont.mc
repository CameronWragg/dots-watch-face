import Toybox.Graphics;
import Toybox.Lang;
import Toybox.StringUtil;

// The dot-matrix font shared by the time, date and weather. Every glyph is 7 rows
// tall; only the dot size and pitch change between uses. Glyphs are separated by
// one empty column.
module DotFont {

    const ROWS = 7;

    // Characters with a glyph, in table order.
    const CHARS = "0123456789CTUE:° ADFHIMNORSW-_";

    // Glyph widths in columns, in CHARS order.
    const WIDTHS = [5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 1, 2, 2,
        5, 5, 5, 5, 3, 5, 5, 5, 5, 5, 5, 3, 5] as Array<Number>;

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
    ] as Array<Number>;

    // Characters of the Glyphs font: a dot, and an empty cell of the same advance.
    const LARGE_DOT = '0';
    const LARGE_GAP = '1';
    const SMALL_DOT = '2';
    const SMALL_GAP = '3';

    const LARGE_SIZE = 6;
    const LARGE_PITCH = 8;
    const SMALL_SIZE = 3;
    const SMALL_PITCH = 4;

    // drawText puts Glyphs font characters 1 px below the y it is given (measured in
    // the simulator; the font's yoffset can't be negative to cancel it).
    const DRAW_Y_CORRECTION = 1;

    // Draws Glyphs font characters with their top-left pixel at (x, y).
    function drawGlyphs(dc as Graphics.Dc, font as Graphics.FontType, x as Number, y as Number, text as String) as Void {
        dc.drawText(x, y - DRAW_Y_CORRECTION, font, text, Graphics.TEXT_JUSTIFY_LEFT);
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

    // Draws a string in the current colour with its top-left dot at (left, top).
    // Each of the 7 rows is one drawText call: a run of dot and gap characters
    // whose advance is the dot pitch.
    function draw(dc as Graphics.Dc, font as Graphics.FontType, text as String, left as Number, top as Number,
            large as Boolean) as Void {
        var cols = columns(text);
        if (cols == 0) {
            return;
        }
        var chars = text.toCharArray();
        var dot = large ? LARGE_DOT : SMALL_DOT;
        var gap = large ? LARGE_GAP : SMALL_GAP;
        var pitch = large ? LARGE_PITCH : SMALL_PITCH;
        var row = new Array<Char>[cols];
        for (var r = 0; r < ROWS; r++) {
            var c = 0;
            for (var i = 0; i < chars.size(); i++) {
                var g = indexOf(chars[i]);
                if (g == null) {
                    continue;
                }
                if (c > 0) {
                    row[c] = gap;
                    c++;
                }
                var bits = GLYPHS[g * ROWS + r];
                for (var k = WIDTHS[g] - 1; k >= 0; k--) {
                    row[c] = (bits >> k) & 1 == 1 ? dot : gap;
                    c++;
                }
            }
            drawGlyphs(dc, font, left, top + r * pitch, StringUtil.charArrayToString(row));
        }
    }
}
