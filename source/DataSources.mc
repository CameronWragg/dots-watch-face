import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Complications;
import Toybox.Lang;
import Toybox.Math;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.UserProfile;
import Toybox.Weather;

// The ring's data points, read once a minute: as fractions from 0 to 1 for the
// bars, and as text for the centre line. Null wherever a value is unavailable.
module DataSources {

    const DEFAULT_RESTING_HR = 50;
    const DEFAULT_MAX_HR = 190;
    const RECOVERY_CAP_HOURS = 96;

    // Resting and maximum heart rate, read from the user profile by
    // refreshHeartRateRange() rather than on every update.
    var _hrRange as [Number, Number]? = null;

    // The fraction for each of the given complication types, sharing one read of
    // each system API.
    function fractions(types as Array<Number>) as Array<Float?> {
        var stats = System.getSystemStats();
        var info = ActivityMonitor.getInfo();
        var out = new Array<Float?>[types.size()];
        for (var i = 0; i < types.size(); i++) {
            out[i] = fraction(types[i], reading(types[i], stats, info), info);
        }
        return out;
    }

    // A complication type's current reading as text, for the centre line: for
    // example 87%, 64, 8432, 12H, or the sunset time. Null when unavailable.
    function valueText(type as Number, is24Hour as Boolean) as String? {
        var value = reading(type, System.getSystemStats(), ActivityMonitor.getInfo());
        if (value == null) {
            return null;
        }
        var whole = Math.round(value.toFloat()).toNumber();
        switch (type) {
            case Complications.COMPLICATION_TYPE_BATTERY:
            case Complications.COMPLICATION_TYPE_SOLAR_INPUT:
            case Complications.COMPLICATION_TYPE_PULSE_OX:
                return (whole < 0 ? 0 : whole) + "%";
            case Complications.COMPLICATION_TYPE_RECOVERY_TIME:
                return whole + "H";
            case Complications.COMPLICATION_TYPE_SUNSET:
                return timeOfDay(whole, is24Hour);
        }
        return whole.toString();
    }

    // Seconds since midnight as H:MM, in 12 or 24 hour time.
    function timeOfDay(seconds as Number, is24Hour as Boolean) as String {
        var hour = seconds / 3600 % 24;
        if (!is24Hour) {
            hour = hour % 12 == 0 ? 12 : hour % 12;
        }
        return hour + ":" + (seconds / 60 % 60).format("%02d");
    }

    // The raw reading behind a complication type, read straight from the system
    // APIs the face already uses where they exist; the Complications API covers
    // the rest. Units are the type's own: percent, bpm, steps, hours, seconds
    // since midnight for Sunset, and so on.
    function reading(type as Number, stats as System.Stats, info as ActivityMonitor.Info) as Numeric? {
        switch (type) {
            case Complications.COMPLICATION_TYPE_BATTERY: return stats.battery;
            case Complications.COMPLICATION_TYPE_HEART_RATE: return heartRate();
            case Complications.COMPLICATION_TYPE_STEPS: return info.steps;
            case Complications.COMPLICATION_TYPE_SOLAR_INPUT: return stats.solarIntensity;
            case Complications.COMPLICATION_TYPE_BODY_BATTERY: return bodyBattery();
            // timeToRecovery is in hours (the RECOVERY_TIME complication would be minutes).
            case Complications.COMPLICATION_TYPE_RECOVERY_TIME: return info.timeToRecovery;
            case Complications.COMPLICATION_TYPE_STRESS:
                // The complication is the stress level Garmin's own faces show;
                // stressScore averages only the last 30 seconds.
                var stress = complication(Complications.COMPLICATION_TYPE_STRESS);
                return stress != null ? stress : info.stressScore;
            case Complications.COMPLICATION_TYPE_FLOORS_CLIMBED: return info.floorsClimbed;
            case Complications.COMPLICATION_TYPE_INTENSITY_MINUTES:
                var week = info.activeMinutesWeek;
                return week != null ? week.total : null;
            case Complications.COMPLICATION_TYPE_PULSE_OX:
            case Complications.COMPLICATION_TYPE_SLEEP_SCORE:
            case Complications.COMPLICATION_TYPE_SUNSET:
                return complication(type as Complications.Type);
        }
        return null;
    }

    // How full a reading's bar is.
    function fraction(type as Number, value as Numeric?, info as ActivityMonitor.Info) as Float? {
        if (value == null) {
            return null;
        }
        switch (type) {
            // Solar intensity is negative while the watch is not charging from the
            // sun, which shows as empty.
            case Complications.COMPLICATION_TYPE_BATTERY:
            case Complications.COMPLICATION_TYPE_SOLAR_INPUT:
            case Complications.COMPLICATION_TYPE_BODY_BATTERY:
            case Complications.COMPLICATION_TYPE_STRESS:
            case Complications.COMPLICATION_TYPE_PULSE_OX:
            case Complications.COMPLICATION_TYPE_SLEEP_SCORE:
                return percent(value);
            case Complications.COMPLICATION_TYPE_HEART_RATE:
                // From resting (empty) to maximum heart rate (full).
                if (_hrRange == null) {
                    refreshHeartRateRange();
                }
                var range = _hrRange as [Number, Number];
                return clamp((value - range[0]).toFloat() / (range[1] - range[0]));
            case Complications.COMPLICATION_TYPE_STEPS: return ratio(value, info.stepGoal);
            case Complications.COMPLICATION_TYPE_FLOORS_CLIMBED: return ratio(value, info.floorsClimbedGoal);
            case Complications.COMPLICATION_TYPE_INTENSITY_MINUTES: return ratio(value, info.activeMinutesWeekGoal);
            // Fills in reverse, so a fuller bar means more ready.
            case Complications.COMPLICATION_TYPE_RECOVERY_TIME:
                return clamp(1.0 - value.toFloat() / RECOVERY_CAP_HOURS);
            case Complications.COMPLICATION_TYPE_SUNSET: return daylight(value.toNumber());
        }
        return null;
    }

    // Current heart rate in bpm, from the activity or else the latest sample.
    function heartRate() as Number? {
        var activity = Activity.getActivityInfo();
        var hr = activity != null ? activity.currentHeartRate : null;
        if (hr == null) {
            var sample = ActivityMonitor.getHeartRateHistory(1, true).next();
            if (sample != null && sample.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
                hr = sample.heartRate;
            }
        }
        return hr;
    }

    // Rereads resting and maximum heart rate from the user profile. They change at
    // most daily, so the view calls this once an hour.
    function refreshHeartRateRange() as Void {
        var profile = UserProfile.getProfile();
        var resting = profile.restingHeartRate;
        if (resting == null) {
            resting = profile.averageRestingHeartRate;
        }
        // The profile has no maximum heart rate field; the top of zone 5 serves as one.
        var zones = UserProfile.getHeartRateZones(UserProfile.HR_ZONE_SPORT_GENERIC);
        var max = zones.size() > 0 ? zones[zones.size() - 1] : null;
        if (resting == null || max == null || max <= resting) {
            resting = DEFAULT_RESTING_HR;
            max = DEFAULT_MAX_HR;
        }
        _hrRange = [resting, max];
    }

    // Progress towards a goal, such as steps against the step goal.
    function ratio(value as Numeric, goal as Number?) as Float? {
        if (goal == null || goal <= 0) {
            return null;
        }
        return clamp(value.toFloat() / goal);
    }

    // A value from 0 to 100, such as stress or sleep score.
    function percent(value as Numeric) as Float {
        return clamp(value.toFloat() / 100.0);
    }

    // Latest Body Battery level, 0 to 100.
    function bodyBattery() as Numeric? {
        var sample = SensorHistory.getBodyBatteryHistory({:period => 1, :order => SensorHistory.ORDER_NEWEST_FIRST}).next();
        return sample != null ? sample.data : null;
    }

    // How much of today's daylight is left: full at sunrise, empty from sunset until
    // the next sunrise. Sunset is in seconds since midnight.
    function daylight(sunset as Number) as Float? {
        var sunrise = complication(Complications.COMPLICATION_TYPE_SUNRISE);
        if (sunrise == null) {
            return null;
        }
        var clock = System.getClockTime();
        return daylightLeft(clock.hour * 3600 + clock.min * 60 + clock.sec, sunrise.toNumber(), sunset);
    }

    // Times are seconds since local midnight.
    function daylightLeft(now as Number, sunrise as Number, sunset as Number) as Float? {
        if (sunset <= sunrise) {
            return null;
        }
        if (now < sunrise || now >= sunset) {
            return 0.0;
        }
        return (sunset - now).toFloat() / (sunset - sunrise);
    }

    // A system complication's numeric value, or null when it is missing or not a number.
    function complication(type as Complications.Type) as Numeric? {
        try {
            var value = Complications.getComplication(new Complications.Id(type)).value;
            return value instanceof Number || value instanceof Float ? value : null;
        } catch (e) {
            return null;
        }
    }

    // Current temperature as a whole number in the watch's unit, or null.
    function temperature(conditions as Weather.CurrentConditions?) as Number? {
        var celsius = conditions != null ? conditions.temperature : null;
        if (celsius == null) {
            return null;
        }
        return displayTemperature(celsius, fahrenheit());
    }

    // A Celsius reading as a whole number in Celsius or Fahrenheit.
    function displayTemperature(celsius as Numeric, inFahrenheit as Boolean) as Number {
        var t = inFahrenheit ? celsius * 9.0 / 5.0 + 32.0 : celsius.toFloat();
        return Math.round(t).toNumber();
    }

    // Weather.CONDITION_* code for the current weather, or null.
    function weatherCondition(conditions as Weather.CurrentConditions?) as Number? {
        return conditions != null ? conditions.condition : null;
    }

    function fahrenheit() as Boolean {
        return System.getDeviceSettings().temperatureUnits == System.UNIT_STATUTE;
    }

    function clamp(f as Float) as Float {
        return f < 0.0 ? 0.0 : (f > 1.0 ? 1.0 : f);
    }
}
