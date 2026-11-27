import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

/// The raw transport in a browser. It never recurses into the app's HTTP zone.
http.Client newBrowserTransport() => BrowserClient();
