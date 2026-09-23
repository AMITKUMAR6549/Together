import 'package:flutter/services.dart';

/// Bridges to a tiny native method (see android/.../MainActivity.kt) that
/// calls Android's `moveTaskToBack`, sending the app to the background
/// without destroying the Activity — which is what keeps the running party
/// (audio + local server) alive when the user presses the system back
/// button instead of using the explicit "End party"/"Leave" action.
///
/// On platforms without this channel (iOS, where there's no back-button
/// concept to intercept in the first place), this is a silent no-op.
const _channel = MethodChannel('together/background');

Future<void> minimizeApp() async {
  try {
    await _channel.invokeMethod('moveTaskToBack');
  } on MissingPluginException {
    // No native handler registered for this platform — nothing to do.
  } on PlatformException {
    // Best-effort: if the native call fails for some other reason, there's
    // no good fallback, so just let the user try again.
  }
}
