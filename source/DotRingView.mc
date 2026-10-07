import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

class DotRingView extends WatchUi.WatchFace {

    // Tops of the text blocks, in display pixels.
    private const DATE_TOP = 57;
    private const TIME_TOP = 103;
    private const WEATHER_TOP = 176;
    private const WEATHER_ICON_TOP = 182;
    private const WEATHER_ICON_SIZE = 16;
    private const WEATHER_ICON_GAP = 6;

    // Glyphs font character for each Weather.CONDITION_* code (0 to 53); a space
    // means no icon. d sun, g partly cloudy, h cloudy, i rain, j snow,
    // k thunderstorm, l fog.
    private const CONDITION_ICONS = "dghijlkjlljikiiijjjjhjgdiiiikllikljlkllldkkjjijjjijjg ";

    private var _font as Graphics.FontType = Graphics.FONT_XTINY;
    private var _cx as Number = 130;
    // Ring dot centres and icon corners, precomputed in onLayout() so onUpdate()
    // does no trigonometry.
    private var _ringDots as Array<Number> = [] as Array<Number>;
    private var _icons as Array<Number> = [] as Array<Number>;

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc as Dc) as Void {
        _font = WatchUi.loadResource(Rez.Fonts.Glyphs) as WatchUi.FontResource;
        _cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        _ringDots = Ring.positions(_cx, cy);
        _icons = Ring.iconPositions(_cx, cy);
    }

    // Redraws the whole face: ring, icons, date, time and weather.
    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        for (var s = 0; s < Ring.SEGMENTS; s++) {
            Ring.drawSegment(dc, _font, _ringDots, _icons, s, DataSources.forSegment(s));
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        drawCentred(dc, dateText(), DATE_TOP, false);
        drawCentred(dc, timeText(), TIME_TOP, true);
        drawWeather(dc);
    }

    private function drawCentred(dc as Dc, text as String, top as Number, large as Boolean) as Void {
        DotFont.draw(dc, _font, text, _cx - DotFont.width(text, large) / 2, top, large);
    }

    private function timeText() as String {
        var clock = System.getClockTime();
        return formatTime(clock.hour, clock.min, System.getDeviceSettings().is24Hour);
    }

    private function dateText() as String {
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        return formatDate(info.day_of_week as Number, info.day);
    }

    // A condition icon, a gap, then the temperature, centred together. Without
    // weather data, two dashes and no icon.
    private function drawWeather(dc as Dc) as Void {
        var temperature = DataSources.temperature();
        if (temperature == null) {
            drawCentred(dc, "--", WEATHER_TOP, false);
            return;
        }
        var text = temperature.toString() + "°" + (DataSources.fahrenheit() ? "F" : "C");
        var icon = conditionIcon(DataSources.weatherCondition());
        var textWidth = DotFont.width(text, false);
        var left = _cx - (textWidth + (icon != null ? WEATHER_ICON_SIZE + WEATHER_ICON_GAP : 0)) / 2;
        if (icon != null) {
            DotFont.drawGlyphs(dc, _font, left, WEATHER_ICON_TOP, icon);
            left += WEATHER_ICON_SIZE + WEATHER_ICON_GAP;
        }
        DotFont.draw(dc, _font, text, left, WEATHER_TOP, false);
    }

    private function conditionIcon(condition as Number?) as String? {
        if (condition == null || condition < 0 || condition >= CONDITION_ICONS.length()) {
            return null;
        }
        var icon = CONDITION_ICONS.substring(condition, condition + 1) as String;
        return icon.equals(" ") ? null : icon;
    }
}

const WEEKDAYS = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"] as Array<String>;

// HH:MM. In 24 hour mode the leading zero stays; in 12 hour mode hours 1 to 9
// leave the first digit's cell empty, and there is no AM or PM marker.
function formatTime(hour as Number, minute as Number, is24Hour as Boolean) as String {
    var hours;
    if (is24Hour) {
        hours = hour.format("%02d");
    } else {
        hour = hour % 12 == 0 ? 12 : hour % 12;
        hours = hour < 10 ? "_" + hour : hour.toString();
    }
    return hours + ":" + minute.format("%02d");
}

// Three-letter weekday and two-digit day of the month, for example TUE 06.
// dayOfWeek runs from 1 (Sunday) to 7, as Gregorian.info reports it.
function formatDate(dayOfWeek as Number, day as Number) as String {
    return WEEKDAYS[dayOfWeek - 1] + " " + day.format("%02d");
}
