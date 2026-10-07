import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Lang;
import Toybox.Math;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.UserProfile;
import Toybox.Weather;

// One function per ring segment. Each returns a fraction from 0 to 1, or null when
// the value is unavailable.
module DataSources {

    const DEFAULT_RESTING_HR = 50;
    const DEFAULT_MAX_HR = 190;
    // timeToRecovery is in hours (the RECOVERY_TIME complication would be minutes).
    const RECOVERY_CAP_HOURS = 96;

    // The fraction for ring segment 0..5, in Ring.COLOURS order.
    function forSegment(segment as Number) as Float? {
        switch (segment) {
            case 0: return battery();
            case 1: return heartRate();
            case 2: return steps();
            case 3: return solarIntensity();
            case 4: return bodyBattery();
            case 5: return recovery();
        }
        return null;
    }

    function battery() as Float? {
        return clamp(System.getSystemStats().battery / 100.0);
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
        return clamp((hr - resting).toFloat() / (max - resting));
    }

    function steps() as Float? {
        var info = ActivityMonitor.getInfo();
        var count = info.steps;
        var goal = info.stepGoal;
        if (count == null || goal == null || goal <= 0) {
            return null;
        }
        return clamp(count.toFloat() / goal);
    }

    // Negative while the watch is not charging from the sun, which shows as empty.
    function solarIntensity() as Float? {
        var solar = System.getSystemStats().solarIntensity;
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
    function recovery() as Float? {
        var hours = ActivityMonitor.getInfo().timeToRecovery;
        if (hours == null) {
            return null;
        }
        return clamp(1.0 - hours.toFloat() / RECOVERY_CAP_HOURS);
    }

    // Current temperature as a whole number in the watch's unit, or null.
    function temperature() as Number? {
        var conditions = Weather.getCurrentConditions();
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
    function weatherCondition() as Number? {
        var conditions = Weather.getCurrentConditions();
        return conditions != null ? conditions.condition : null;
    }

    function fahrenheit() as Boolean {
        return System.getDeviceSettings().temperatureUnits == System.UNIT_STATUTE;
    }

    function clamp(f as Float) as Float {
        return f < 0.0 ? 0.0 : (f > 1.0 ? 1.0 : f);
    }
}
