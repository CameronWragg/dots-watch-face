import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Weather;
import Toybox.WatchUi;

class DotRingView extends WatchUi.WatchFace {

    // Tops of the text blocks, in display pixels. The centre line below the time
    // shows the weather, or a segment's exact value after a touch and hold.
    private const DATE_TOP = 57;
    private const TIME_TOP = 103;
    private const CENTRE_TOP = 176;
    private const CENTRE_ICON_TOP = 182;
    private const CENTRE_ICON_GAP = 6;
    // The row of status icons, between the centre line and the bottom segment's icon.
    private const STATUS_TOP = 207;
    private const STATUS_GAP = 4;
    // How long a segment's exact value stays on the centre line, in milliseconds.
    private const VALUE_MS = 5000;

    // Status icons in display order, with the bit each sets in statusBits().
    private const STATUS_ICONS = [Icons.NOTIFICATIONS, Icons.PHONE_DISCONNECTED, Icons.ALARM, Icons.DO_NOT_DISTURB]
        as Array<Number>;

    // Icon for each Weather.CONDITION_* code (0 to 53), or -1 for none.
    private const CONDITION_ICONS = [
        Icons.SUN, Icons.PARTLY_CLOUDY, Icons.CLOUDY, Icons.RAIN, Icons.SNOW, Icons.FOG,
        Icons.THUNDERSTORM, Icons.SNOW, Icons.FOG, Icons.FOG, Icons.SNOW, Icons.RAIN,
        Icons.THUNDERSTORM, Icons.RAIN, Icons.RAIN, Icons.RAIN, Icons.SNOW, Icons.SNOW,
        Icons.SNOW, Icons.SNOW, Icons.CLOUDY, Icons.SNOW, Icons.PARTLY_CLOUDY, Icons.SUN,
        Icons.RAIN, Icons.RAIN, Icons.RAIN, Icons.RAIN, Icons.THUNDERSTORM, Icons.FOG,
        Icons.FOG, Icons.RAIN, Icons.THUNDERSTORM, Icons.FOG, Icons.SNOW, Icons.FOG,
        Icons.THUNDERSTORM, Icons.FOG, Icons.FOG, Icons.FOG, Icons.SUN, Icons.THUNDERSTORM,
        Icons.THUNDERSTORM, Icons.SNOW, Icons.SNOW, Icons.RAIN, Icons.SNOW, Icons.SNOW,
        Icons.SNOW, Icons.RAIN, Icons.SNOW, Icons.SNOW, Icons.PARTLY_CLOUDY, -1,
    ] as Array<Number>;

    private var _width as Number = 260;
    private var _height as Number = 260;
    private var _cx as Number = 130;
    // Ring dot centres and icon corners, precomputed in onLayout() so onUpdate()
    // does no trigonometry.
    private var _ringDots as Array<Number> = [] as Array<Number>;
    private var _icons as Array<Number> = [] as Array<Number>;

    // The rendered face. Each minute only what changed is redrawn into it, and every
    // onUpdate() copies it to the screen in one call: in high-power mode onUpdate()
    // runs every second, but nothing on the face changes more often than once a minute.
    private var _frame as Graphics.BufferedBitmapReference? = null;

    // What the frame currently shows. _time is null until the frame is first drawn.
    private var _minute as Number = -1;
    private var _hour as Number = -1;
    private var _lit as Array<Number> = [-1, -1, -1, -1, -1, -1] as Array<Number>;
    private var _time as String? = null;
    private var _date as String? = null;
    private var _centreText as String? = null;
    private var _centreIcon as Number? = null;
    private var _centreIconColour as Number = 0;
    private var _status as Number = -1;
    // Areas covered by the date, centre line and status row, as [left, top, width, height].
    private var _dateBox as Array<Number>? = null;
    private var _centreBox as Array<Number>? = null;
    private var _statusBox as Array<Number>? = null;
    // Left edge of the time's colon, which blinks while the watch is awake.
    private var _colonX as Number = 0;

    // Whether the watch is awake after a wrist raise, with onUpdate() every second.
    private var _awake as Boolean = false;
    // The segment whose exact value the centre line shows, or -1 for the weather,
    // and when it was chosen (System.getTimer() milliseconds).
    private var _shown as Number = -1;
    private var _shownAt as Number = 0;

    // Whether the watch face editor started the face. The editor pulses the segment
    // being edited, drawn by a SegmentDrawable, so the face itself leaves it out.
    private var _editMode as Boolean;
    private var _selected as Number = -1;
    private var _hidden as Number = -1;

    function initialize(editMode as Boolean) {
        WatchFace.initialize();
        _editMode = editMode;
        Settings.load();
    }

    function onLayout(dc as Dc) as Void {
        _width = dc.getWidth();
        _height = dc.getHeight();
        _cx = _width / 2;
        var cy = _height / 2;
        _ringDots = Ring.positions(_cx, cy);
        _icons = Ring.iconPositions(_cx, cy);
        // In the editor the face is drawn from scratch every time, without a frame.
        _frame = _editMode ? null : createFrame();
        invalidate();
    }

    // The watch face editor saves its settings while the face is not running, so
    // check for changes whenever the face comes back, and redraw with a new frame
    // for the new colours.
    function onShow() as Void {
        if (Settings.load() && _frame != null) {
            _frame = createFrame();
            invalidate();
            WatchUi.requestUpdate();
        }
    }

    // A frame buffer whose palette holds only the colours the face uses, so it
    // needs at most 4 bits per pixel.
    private function createFrame() as Graphics.BufferedBitmapReference {
        var palette = [Graphics.COLOR_BLACK, Ring.UNLIT_COLOUR] as Array<Number>;
        if (palette.indexOf(Settings.accent) < 0) {
            palette.add(Settings.accent);
        }
        for (var s = 0; s < Ring.SEGMENTS; s++) {
            if (palette.indexOf(Settings.colours[s]) < 0) {
                palette.add(Settings.colours[s]);
            }
        }
        return Graphics.createBufferedBitmap({:width => _width, :height => _height, :palette => palette});
    }

    // Awake after a wrist raise: refresh straight away, so what the wearer sees is
    // current, then blink the colon each second.
    function onExitSleep() as Void {
        _awake = true;
        _minute = -1;
    }

    // Back to once a minute: steady colon, and the weather back on the centre line.
    function onEnterSleep() as Void {
        _awake = false;
        if (_shown >= 0) {
            _shown = -1;
            _minute = -1;
        }
        WatchUi.requestUpdate();
    }

    // Shows a segment's exact value on the centre line for a few seconds, after a
    // touch and hold on it. Takes the editor slot of the segment, as slotAt() returns.
    function showValue(slot as Number) as Void {
        _shown = slot - 1;
        _shownAt = System.getTimer();
        _minute = -1;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        var clock = System.getClockTime();
        if (_editMode) {
            // Settings change with every step in the editor: draw from scratch.
            invalidate();
            refresh(dc, clock);
            return;
        }
        if (_shown >= 0 && System.getTimer() - _shownAt >= VALUE_MS) {
            _shown = -1;
            _minute = -1;
        }
        var minute = clock.hour * 60 + clock.min;
        var frame = _frame != null ? _frame.get() as Graphics.BufferedBitmap? : null;
        if (frame == null) {
            // The system reclaimed the frame's memory: draw straight to the screen,
            // and rebuild the frame for the next update.
            invalidate();
            refresh(dc, clock);
            invalidate();
            _frame = createFrame();
            return;
        }
        if (minute != _minute) {
            refresh(frame.getDc(), clock);
            _minute = minute;
        }
        dc.drawBitmap(0, 0, frame);

        // The colon is off every other second while awake. Drawn over the copy on
        // screen only, so the frame always holds it.
        if (_awake && clock.sec % 2 == 1) {
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(_colonX, TIME_TOP, DotFont.LARGE_SIZE, DotFont.height(true));
        }
    }

    // Forgets what the frame shows, so the next refresh redraws all of it.
    private function invalidate() as Void {
        _minute = -1;
        _time = null;
        _date = null;
        _centreText = null;
        _centreIcon = null;
        _status = -1;
        _dateBox = null;
        _centreBox = null;
        _statusBox = null;
        for (var s = 0; s < Ring.SEGMENTS; s++) {
            _lit[s] = -1;
        }
    }

    // Reads the data and redraws whatever differs from what dc already shows.
    private function refresh(dc as Dc, clock as System.ClockTime) as Void {
        if (_time == null) {
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
            dc.clear();
        }
        if (clock.hour != _hour) {
            DataSources.refreshHeartRateRange();
            _hour = clock.hour;
        }

        var data = Settings.data;
        var fractions = DataSources.fractions(data);
        for (var s = 0; s < Ring.SEGMENTS; s++) {
            var lit = Ring.litCount(fractions[s]);
            if (lit != _lit[s] && s != _hidden) {
                Ring.drawSegment(dc, _ringDots, _icons, s, Settings.colours[s], Choices.ICONS[data[s]], _lit[s], lit);
            }
            _lit[s] = lit;
        }

        var date = dateText();
        if (!date.equals(_date)) {
            clearBox(dc, _dateBox);
            _dateBox = drawCentred(dc, date, DATE_TOP, false);
            _date = date;
        }

        var settings = System.getDeviceSettings();
        var time = formatTime(clock.hour, clock.min, settings.is24Hour);
        var timeLeft = _cx - DotFont.width(time, true) / 2;
        _colonX = timeLeft + (DotFont.columns(time.substring(0, 2) as String) + 1) * DotFont.LARGE_PITCH;
        if (_time == null) {
            dc.setColor(Settings.accent, Graphics.COLOR_TRANSPARENT);
            DotFont.draw(dc, time, timeLeft, TIME_TOP, true);
        } else {
            // Every time string has the same glyph widths, so only changed digits move.
            DotFont.redrawChanged(dc, _time, time, timeLeft, TIME_TOP, true, Settings.accent);
        }
        _time = time;

        drawCentreLine(dc, settings);
        drawStatus(dc, settings);
    }

    // Draws accent-coloured text centred on the display and returns the area it covers.
    private function drawCentred(dc as Dc, text as String, top as Number, large as Boolean) as Array<Number> {
        var width = DotFont.width(text, large);
        var left = _cx - width / 2;
        dc.setColor(Settings.accent, Graphics.COLOR_TRANSPARENT);
        DotFont.draw(dc, text, left, top, large);
        return [left, top, width, DotFont.height(large)] as Array<Number>;
    }

    private function clearBox(dc as Dc, box as Array<Number>?) as Void {
        if (box != null) {
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(box[0], box[1], box[2], box[3]);
        }
    }

    private function dateText() as String {
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        return formatDate(info.day_of_week as Number, info.day);
    }

    // The centre line: an icon, a gap, then text, centred together. Normally the
    // weather's condition icon and temperature, or two dashes and no icon without
    // weather data; after a touch and hold, the segment's icon and exact value.
    // Redrawn only when it changes.
    private function drawCentreLine(dc as Dc, settings as System.DeviceSettings) as Void {
        var text = null;
        var icon = null;
        var iconColour = Settings.accent;
        if (_shown >= 0) {
            text = DataSources.valueText(Settings.data[_shown], settings.is24Hour);
            icon = Choices.ICONS[Settings.data[_shown]];
            iconColour = Settings.colours[_shown];
            if (text == null) {
                text = "--";
            }
        } else {
            var conditions = Weather.getCurrentConditions();
            var temperature = DataSources.temperature(conditions);
            if (temperature == null) {
                text = "--";
            } else {
                text = temperature.toString() + "°" + (DataSources.fahrenheit() ? "F" : "C");
                icon = conditionIcon(DataSources.weatherCondition(conditions));
            }
        }
        if (text.equals(_centreText) && icon == _centreIcon && iconColour == _centreIconColour) {
            return;
        }
        clearBox(dc, _centreBox);
        _centreText = text;
        _centreIcon = icon;
        _centreIconColour = iconColour;
        if (icon == null) {
            _centreBox = drawCentred(dc, text, CENTRE_TOP, false);
            return;
        }
        var width = Icons.SIZE + CENTRE_ICON_GAP + DotFont.width(text, false);
        var left = _cx - width / 2;
        dc.setColor(iconColour, Graphics.COLOR_TRANSPARENT);
        Icons.draw(dc, icon, left, CENTRE_ICON_TOP);
        dc.setColor(Settings.accent, Graphics.COLOR_TRANSPARENT);
        DotFont.draw(dc, text, left + Icons.SIZE + CENTRE_ICON_GAP, CENTRE_TOP, false);
        // The 27 px text spans the 16 px icon's rows too (176 to 203 against 182 to 198).
        _centreBox = [left, CENTRE_TOP, width, DotFont.height(false)] as Array<Number>;
    }

    // The status icons that apply, centred in a row: unread notifications, phone
    // not connected, an alarm set, Do Not Disturb. Redrawn only when they change.
    private function drawStatus(dc as Dc, settings as System.DeviceSettings) as Void {
        var bits = statusBits(settings);
        if (bits == _status) {
            return;
        }
        clearBox(dc, _statusBox);
        _status = bits;
        _statusBox = null;
        var count = 0;
        for (var i = 0; i < STATUS_ICONS.size(); i++) {
            count += (bits >> i) & 1;
        }
        if (count == 0) {
            return;
        }
        var width = count * Icons.STATUS_SIZE + (count - 1) * STATUS_GAP;
        var x = _cx - width / 2;
        _statusBox = [x, STATUS_TOP, width, Icons.STATUS_SIZE] as Array<Number>;
        dc.setColor(Settings.accent, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < STATUS_ICONS.size(); i++) {
            if ((bits >> i) & 1 == 1) {
                Icons.draw(dc, STATUS_ICONS[i], x, STATUS_TOP);
                x += Icons.STATUS_SIZE + STATUS_GAP;
            }
        }
    }

    // Touch and watch face editor support

    // Picks up a change made in the editor. While a complication is being chosen, the
    // editor pulses its segment, so the face stops drawing it.
    function onConfigEdited(type as WatchUi.WatchFaceConfigType?) as Void {
        Settings.load();
        _hidden = type == WatchUi.WATCH_FACE_CONFIG_TYPE_COMPLICATION ? _selected : -1;
        WatchUi.requestUpdate();
    }

    // The drawable the editor pulses for a segment (editor slot ids are segment
    // numbers plus one), with the segment hidden from the face meanwhile.
    function segmentDrawable(slot as Number?) as WatchUi.ComplicationDrawableRef? {
        if (slot == null || slot < 1 || slot > Ring.SEGMENTS) {
            return null;
        }
        var segment = slot - 1;
        _selected = segment;
        _hidden = segment;
        WatchUi.requestUpdate();
        var drawable = new SegmentDrawable(self, segment);
        return new WatchUi.ComplicationDrawableRef({:drawable => drawable, :boundingBox => segmentBox(segment)});
    }

    // Draws one segment as it currently stands, for SegmentDrawable.
    function drawSegmentAlone(dc as Dc, segment as Number) as Void {
        var lit = _lit[segment] >= 0 ? _lit[segment] : 0;
        Ring.drawSegment(dc, _ringDots, _icons, segment, Settings.colours[segment],
            Choices.ICONS[Settings.data[segment]], -1, lit);
    }

    // The area covering a segment's dots and icon.
    function segmentBox(segment as Number) as Graphics.BoundingBox {
        var box = new Graphics.BoundingBox();
        var first = segment * Ring.DOTS_PER_SEGMENT * 2;
        for (var k = first; k < first + Ring.DOTS_PER_SEGMENT * 2; k += 2) {
            box.addRectangle(_ringDots[k] - Ring.LIT_SIZE / 2, _ringDots[k + 1] - Ring.LIT_SIZE / 2,
                Ring.LIT_SIZE, Ring.LIT_SIZE);
        }
        box.addRectangle(_icons[2 * segment], _icons[2 * segment + 1], Icons.SIZE, Icons.SIZE);
        return box;
    }

    // The editor slot (segment number plus one) of the segment at a touched point,
    // or null when the touch is nowhere near the ring.
    function slotAt(x as Number, y as Number) as Number? {
        var dx = x - _cx;
        var dy = _height / 2 - y;
        if (dx * dx + dy * dy < Ring.TAP_RADIUS * Ring.TAP_RADIUS) {
            return null;
        }
        // Angle clockwise from 12 o'clock, to the nearest segment centre.
        var degrees = Math.toDegrees(Math.atan2(dx, dy));
        var segment = Math.round(degrees / Ring.SEGMENT_STEP_DEGREES).toNumber();
        return (segment + Ring.SEGMENTS) % Ring.SEGMENTS + 1;
    }

    private function conditionIcon(condition as Number?) as Number? {
        if (condition == null || condition < 0 || condition >= CONDITION_ICONS.size()) {
            return null;
        }
        var icon = CONDITION_ICONS[condition];
        return icon < 0 ? null : icon;
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

// One bit per status icon, in DotRingView.STATUS_ICONS order: unread notifications,
// phone not connected, an alarm set, Do Not Disturb.
function statusBits(settings as System.DeviceSettings) as Number {
    return (settings.notificationCount > 0 ? 1 : 0)
        | (settings.phoneConnected ? 0 : 2)
        | (settings.alarmCount > 0 ? 4 : 0)
        | (settings.doNotDisturb ? 8 : 0);
}

// A segment drawn on its own, for the watch face editor to pulse while the wearer
// chooses its complication. The editor draws it with the screen's origin.
class SegmentDrawable extends WatchUi.Drawable {

    private var _view as DotRingView;
    private var _segment as Number;

    function initialize(view as DotRingView, segment as Number) {
        Drawable.initialize({});
        _view = view;
        _segment = segment;
    }

    function draw(dc as Dc) as Void {
        _view.drawSegmentAlone(dc, _segment);
    }
}
