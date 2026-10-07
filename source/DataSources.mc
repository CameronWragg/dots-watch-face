import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Lang;
import Toybox.Math;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.UserProfile;
import Toybox.Weather;

// One function per ring segment. Each returns a fraction from 0 to 1, or null when
// the value is unavailable. segments() reads the system once for all six.
module DataSources {

    const DEFAULT_RESTING_HR = 50;
    const DEFAULT_MAX_HR = 190;
    // timeToRecovery is in hours (the RECOVERY_TIME complication would be minutes).
    const RECOVERY_CAP_HOURS = 96;

    // Resting and maximum heart rate, read from the user profile by
    // refreshHeartRateRange() rather than on every update.
    var _hrRange as [Number, Number]? = null;

    // The six ring fractions, in Ring.COLOURS order, sharing one read of each system API.
    function segments() as Array<Float?> {
        var stats = System.getSystemStats();
        var info = ActivityMonitor.getInfo();
        return [battery(stats), heartRate(), steps(info), solarIntensity(stats), bodyBattery(), recovery(info)]
            as Array<Float?>;
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

    function steps(info as ActivityMonitor.Info) as Float? {
        var count = info.steps;
        var goal = info.stepGoal;
        if (count == null || goal == null || goal <= 0) {
            return null;
        }
        return clamp(count.toFloat() / goal);
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
