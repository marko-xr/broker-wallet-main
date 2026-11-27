import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Browser key for the Maps JavaScript API, supplied at build time. It is a
/// public key: restrict it in Google Cloud by HTTP referrer to the web app's
/// own origins and to the Maps JavaScript API only.
const String _key = String.fromEnvironment('GOOGLE_MAPS_WEB_API_KEY');

/// Loads the Maps JavaScript API before the app starts, so every map in the
/// app finds it. Without a key it does nothing and maps stay unavailable in
/// the browser. A slow or failed load never blocks the app for long.
Future<void> loadGoogleMapsForWeb() async {
  if (_key.isEmpty) return;
  final google = globalContext['google'];
  if (google is JSObject && google['maps'] != null) return;

  final done = Completer<void>();
  void finish(JSAny? _) {
    if (!done.isCompleted) done.complete();
  }

  final document = globalContext['document'] as JSObject;
  final script =
      document.callMethod<JSObject>('createElement'.toJS, 'script'.toJS);
  script['src'] = Uri.https('maps.googleapis.com', '/maps/api/js', {
    'key': _key,
  }).toString().toJS;
  script['onload'] = finish.toJS;
  script['onerror'] = finish.toJS;
  (document['head'] as JSObject).callMethod<JSAny?>('appendChild'.toJS, script);
  await done.future.timeout(const Duration(seconds: 8), onTimeout: () {});
}
