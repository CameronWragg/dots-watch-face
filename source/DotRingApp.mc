import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class DotRingApp extends Application.AppBase {

    // Whether the watch face editor started the app, to show the face for editing.
    private var _editMode as Boolean = false;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
        if (state != null && state[:launchedFromWatchFaceSettingsEditor] == true) {
            _editMode = true;
        }
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var view = new DotRingView(_editMode);
        return [view, new DotRingDelegate(view)];
    }
}
