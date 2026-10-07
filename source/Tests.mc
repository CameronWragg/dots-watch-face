import Toybox.Lang;
import Toybox.Test;

// Unit tests, excluded from normal builds. Run with:
//   monkeyc ... --unit-test -o bin/test.prg && monkeydo bin/test.prg fenix8solar47mm -t

(:test)
function ringFillsByRoundedFraction(logger as Logger) as Boolean {
    Test.assertEqual(Ring.litCount(null), 0);
    Test.assertEqual(Ring.litCount(0.0), 0);
    Test.assertEqual(Ring.litCount(0.5), 7);
    Test.assertEqual(Ring.litCount(1.0), 13);
    Test.assertEqual(Ring.litCount(-0.2), 0);
    Test.assertEqual(Ring.litCount(1.5), 13);
    return true;
}

(:test)
function ringHas78DotsInsideTheDisplay(logger as Logger) as Boolean {
    var dots = Ring.positions(130, 130);
    Test.assertEqual(dots.size(), 156);
    // Segment 0's first dot is 24 degrees before 12 o'clock.
    Test.assertEqual(dots[0], 80);
    Test.assertEqual(dots[1], 19);
    for (var i = 0; i < dots.size(); i++) {
        Test.assert(dots[i] >= 3 && dots[i] <= 257);
    }
    return true;
}

(:test)
function timeBlockIs25ColumnsAnd198Pixels(logger as Logger) as Boolean {
    Test.assertEqual(DotFont.columns("10:09"), 25);
    Test.assertEqual(DotFont.width("10:09", true), 198);
    Test.assertEqual(DotFont.columns("_9:41"), 25);
    return true;
}

(:test)
function timeIn24HourMode(logger as Logger) as Boolean {
    Test.assertEqual(formatTime(0, 5, true), "00:05");
    Test.assertEqual(formatTime(9, 30, true), "09:30");
    Test.assertEqual(formatTime(23, 59, true), "23:59");
    return true;
}

(:test)
function timeIn12HourMode(logger as Logger) as Boolean {
    Test.assertEqual(formatTime(0, 0, false), "12:00");
    Test.assertEqual(formatTime(1, 7, false), "_1:07");
    Test.assertEqual(formatTime(9, 59, false), "_9:59");
    Test.assertEqual(formatTime(10, 9, false), "10:09");
    Test.assertEqual(formatTime(12, 30, false), "12:30");
    Test.assertEqual(formatTime(13, 0, false), "_1:00");
    Test.assertEqual(formatTime(23, 15, false), "11:15");
    return true;
}

(:test)
function everyWeekdayHasGlyphs(logger as Logger) as Boolean {
    for (var d = 1; d <= 7; d++) {
        var text = formatDate(d, 6);
        var chars = text.toCharArray();
        for (var i = 0; i < chars.size(); i++) {
            Test.assertMessage(DotFont.indexOf(chars[i]) != null, "no glyph for " + chars[i] + " in " + text);
        }
    }
    Test.assertEqual(formatDate(3, 6), "TUE 06");
    Test.assertEqual(formatDate(1, 31), "SUN 31");
    return true;
}

(:test)
function temperatureBelowZeroAndInFahrenheit(logger as Logger) as Boolean {
    Test.assertEqual(DataSources.displayTemperature(14, false), 14);
    Test.assertEqual(DataSources.displayTemperature(-5, false), -5);
    Test.assertEqual(DataSources.displayTemperature(-5, true), 23);
    Test.assertEqual(DataSources.displayTemperature(-20, true), -4);
    Test.assertEqual(DataSources.displayTemperature(14.4, true), 58);
    var chars = "-4°F --".toCharArray();
    for (var i = 0; i < chars.size(); i++) {
        Test.assert(DotFont.indexOf(chars[i]) != null);
    }
    return true;
}
