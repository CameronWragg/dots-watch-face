import Toybox.Application.WatchFaceConfig;
import Toybox.Lang;
import Toybox.WatchUi;

// Touch input for the face. Normally a touch and hold on a segment shows its exact
// value. In the watch face editor, it passes on edits, gives the editor each
// segment to highlight, and lets a tap on the ring pick a segment.
class DotRingDelegate extends WatchUi.WatchFaceDelegate {

    private var _view as DotRingView;

    function initialize(view as DotRingView) {
        WatchFaceDelegate.initialize();
        _view = view;
    }

    function onPress(clickEvent as WatchUi.ClickEvent) as Boolean {
        var point = clickEvent.getCoordinates();
        var slot = _view.slotAt(point[0], point[1]);
        if (slot == null) {
            return false;
        }
        _view.showValue(slot);
        return true;
    }

    function onWatchFaceConfigEdited(options as {:configId as WatchFaceConfig.Id, :type as WatchUi.WatchFaceConfigType?,
            :committed as Boolean}) as Void {
        _view.onConfigEdited(options[:type] as WatchUi.WatchFaceConfigType?);
    }

    function getComplicationDrawable(complication as WatchFaceConfig.ComplicationRef) as WatchUi.Drawable
            or WatchUi.ComplicationDrawableRef or Null {
        return _view.segmentDrawable(complication.uniqueIdentifier);
    }

    function onTap(clickEvent as WatchUi.ClickEvent) as Boolean {
        var point = clickEvent.getCoordinates();
        var slot = _view.slotAt(point[0], point[1]);
        if (slot == null) {
            return false;
        }
        setSelectedComplication(slot);
        return true;
    }
}
