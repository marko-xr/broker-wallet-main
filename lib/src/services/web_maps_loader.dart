/// Loads the Google Maps JavaScript API that maps need in a browser.
library;

export 'web_maps_loader_stub.dart'
    if (dart.library.js_interop) 'web_maps_loader_web.dart';
