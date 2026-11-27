import 'package:http/http.dart' as http;

/// Only a browser build has this transport.
http.Client newBrowserTransport() =>
    throw UnsupportedError('No browser transport on this platform');
