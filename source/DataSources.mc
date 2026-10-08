import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Complications;
import Toybox.Lang;
import Toybox.Math;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.UserProfile;
import Toybox.Weather;

// One function per data point. Each returns a fraction from 0 to 1, or null when
// the value is unavailable. fractions() reads the system once for all six segments.
module DataSources {

    const DEFAULT_RESTING_HR = 50;
    const DEFAULT_MAX_HR = 190;
    // timeToRecovery is in hours (the RECOVERY_TIME complication would be minutes).
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
            out[i] = forData(types[i], stats, info);
        }
        return out;
    }

    // The fraction for one complication type. Values come from the system APIs the
    // face already uses where they exist; the Complications API covers the rest.
    function forData(type as Number, stats as System.Stats, info as ActivityMonitor.Info) as Float? {
        switch (type) {
            case Complications.COMPLICATION_TYPE_BATTERY: return battery(stats);
            case Complications.COMPLICATION_TYPE_HEART_RATE: return heartRate();
            case Complications.COMPLICATION_TYPE_STEPS: return ratio(info.steps, info.stepGoal);
            case Complications.COMPLICATION_TYPE_SOLAR_INPUT: return solarIntensity(stats);
            case Complications.COMPLICATION_TYPE_BODY_BATTERY: return bodyBattery();
            case Complications.COMPLICATION_TYPE_RECOVERY_TIME: return recovery(info);
            case Complications.COMPLICATION_TYPE_STRESS:
                // The complication is the stress level Garmin's own faces show;
                // stressScore averages only the last 30 seconds.
                var stress = complication(Complications.COMPLICATION_TYPE_STRESS);
                return percent(stress != null ? stress : info.stressScore);
            case Complications.COMPLICATION_TYPE_FLOORS_CLIMBED: return ratio(info.floorsClimbed, info.floorsClimbedGoal);
            case Complications.COMPLICATION_TYPE_INTENSITY_MINUTES:
                var week = info.activeMinutesWeek;
                return week != null ? ratio(week.total, info.activeMinutesWeekGoal) : null;
            case Complications.COMPLICATION_TYPE_PULSE_OX: return percent(complication(Complications.COMPLICATION_TYPE_PULSE_OX));
            case Complications.COMPLICATION_TYPE_SLEEP_SCORE: return percent(complication(Complications.COMPLICATION_TYPE_SLEEP_SCORE));
            // Offered in the editor as Sunset.
            case Complications.COMPLICATION_TYPE_SUNSET: return daylight();
        }
        return null;
    }

    function battery(stats as System.Stats) as Float? {
        return clamp(stats.battery / 100.0);
    }

    // Current heart rate between resting (empty) and maximum (full).
    function heartRate() as Float? {
        var hr = null;
        var activity = Activity.getActivityInfo();
        if (activity != null) {
            hr = activity.currentHeartRate;
        }
        if (hr == null) {
            var sample = ActivityMonitor.getHeartRateHistory(1, true).next();
            if (sample != null && sample.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
                hr = sample.heartRate;
            }
        }
        if (hr == null) {
            return null;
        }
        if (_hrRange == null) {
            refreshHeartRateRange();
        }
        var range = _hrRange as [Number, Number];
        return clamp((hr - range[0]).toFloat() / (range[1] - range[0]));
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
    function ratio(value as Number?, goal as Number?) as Float? {
        if (value == null || goal == null || goal <= 0) {
            return null;
        }
        return clamp(value.toFloat() / goal);
    }

    // A value from 0 to 100, such as stress or sleep score.
    function percent(value as Numeric?) as Float? {
        return value != null ? clamp(value.toFloat() / 100.0) : null;
    }

    // Negative while the watch is not charging from the sun, which shows as empty.
    function solarIntensity(stats as System.Stats) as Float? {
        var solar = stats.solarIntensity;
        if (solar == null) {
            return null;
        }
        return clamp(solar / 100.0);
    }

    function bodyBattery() as Float? {
        var history = SensorHistory.getBodyBatteryHistory({:period => 1, :order => SensorHistory.ORDER_NEWEST_FIRST});
        var sample = history.next();
        var level = sample != null ? sample.data : null;
        if (level == null) {
            return null;
        }
        return clamp(level / 100.0);
    }

    // Fills in reverse, so a fuller bar means more ready.
    function recovery(info as ActivityMonitor.Info) as Float? {
        var hours = info.timeToRecovery;
        if (hours == null) {
            return null;
        }
        return clamp(1.0 - hours.toFloat() / RECOVERY_CAP_HOURS);
    }

    // How much of today's daylight is left: full at sunrise, empty from sunset until
    // the next sunrise.
    function daylight() as Float? {
        var sunrise = complication(Complications.COMPLICATION_TYPE_SUNRISE);
        var sunset = complication(Complications.COMPLICATION_TYPE_SUNSET);
        if (sunrise == null || sunset == null) {
            return null;
        }
        var clock = System.getClockTime();
        return daylightLeft(clock.hour * 3600 + clock.min * 60 + clock.sec, sunrise.toNumber(), sunset.toNumber());
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
