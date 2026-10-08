import Toybox.Application.WatchFaceConfig;
import Toybox.Lang;

// What the wearer chose in the watch face editor (Watch Face menu, Customise): each
// segment's complication type, the colour scheme, and the accent colour for the
// time, date and weather.
module Settings {

    // Complication type and colour of each segment, clockwise from the top.
    var data as Array<Number> = [] as Array<Number>;
    var colours as Array<Number> = [] as Array<Number>;
    var accent as Number = Choices.DEFAULT_ACCENT_COLOUR;

    // Rereads the editor's settings, using the defaults for anything not chosen.
    // Returns whether anything differs from before.
    function load() as Boolean {
        var newData = Choices.DEFAULT_DATA.slice(0, null);
        var scheme = Choices.DEFAULT_SCHEME;
        var dataColour = Choices.DEFAULT_DATA_COLOUR;
        var newAccent = Choices.DEFAULT_ACCENT_COLOUR;

        var config = WatchFaceConfig.getSettings(null);
        if (config != null) {
            var style = config.styleId;
            if (style != null && style > 0 && style < Choices.SCHEMES.size()) {
                scheme = style;
            }
            dataColour = colourOf(config.complicationColor, dataColour);
            newAccent = colourOf(config.accentColor, newAccent);
            var slots = config.complicationSettings;
            if (slots != null) {
                for (var i = 0; i < slots.size(); i++) {
                    // Editor slot ids are the segment numbers plus one.
                    var segment = slots[i].uniqueIdentifier;
                    var id = slots[i].complicationId;
                    if (segment != null && segment >= 1 && segment <= Ring.SEGMENTS && id != null) {
                        var type = id.getType();
                        if (type != null && type >= 0 && type < Choices.ICONS.size() && Choices.ICONS[type] >= 0) {
                            newData[segment - 1] = type;
                        }
                    }
                }
            }
        }

        var schemeColours = Choices.SCHEMES[scheme];
        var newColours = new Array<Number>[Ring.SEGMENTS];
        for (var s = 0; s < Ring.SEGMENTS; s++) {
            newColours[s] = schemeColours != null ? schemeColours[s] : dataColour;
        }

        var changed = data.size() != Ring.SEGMENTS || newAccent != accent;
        for (var s = 0; s < Ring.SEGMENTS && !changed; s++) {
            changed = newData[s] != data[s] || newColours[s] != colours[s];
        }
        data = newData;
        colours = newColours;
        accent = newAccent;
        return changed;
    }

    function colourOf(colour as WatchFaceConfig.Color?, fallback as Number) as Number {
        var value = colour != null ? colour.color : null;
        return value != null ? value as Number : fallback;
    }
}
