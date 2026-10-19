import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String view = 'lib/src/views/Screens/home/Toolkit/uae_links_view.dart';
const String services = 'lib/src/services/uae_links';
const String models = 'lib/src/data/models';

/// The code of [file] without its comments.
String code(File file) => file.readAsStringSync().split('\n').map((line) {
      final at = line.indexOf('//');
      return at < 0 ? line : line.substring(0, at);
    }).join('\n');

List<File> sources() => [
      File(view),
      File('$models/uae_links_model.dart'),
      File('$models/uae_links_catalogue.dart'),
      ...Directory(services)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')),
    ];

/// Facts about the code that no behaviour test would notice breaking.
void main() {
  test('government sign-in stays in the phone browser: no WebView or proxy',
      () {
    for (final file in sources()) {
      final text = code(file).toLowerCase();
      expect(text.contains('webview'), isFalse, reason: file.path);
      expect(text.contains('inappwebview'), isFalse, reason: file.path);
      expect(text.contains('http.get'), isFalse, reason: file.path);
      expect(text.contains('package:http'), isFalse, reason: file.path);
      expect(text.contains('package:dio'), isFalse, reason: file.path);
    }
  });

  test('the screen opens addresses only through the policy-checked launcher',
      () {
    final screen = code(File(view));
    expect(screen.contains('launchUrl'), isFalse);
    expect(screen.contains('canLaunchUrl'), isFalse);
    expect(screen.contains('package:url_launcher'), isFalse);
    expect(screen.contains('launcher.open('), isTrue);

    final launcher = code(File('$services/uae_link_launcher.dart'));
    expect(launcher.contains('UaeLinkUrlPolicy.parse'), isTrue);
    expect(launcher.contains('LaunchMode.externalApplication'), isTrue);
  });

  test('no account, token or Supabase identity can reach a directory address',
      () {
    for (final file in sources()) {
      final text = code(file).toLowerCase();
      for (final word in [
        'supabase',
        'currentuserid',
        'accesstoken',
        'authrepository',
        'firebase',
      ]) {
        expect(text.contains(word), isFalse, reason: '${file.path}: $word');
      }
    }
  });

  test('the report is built from fixed fields only, and never sent silently',
      () {
    final report = code(File('$services/uae_link_report.dart'));
    expect(report.contains('Uri('), isFalse);
    expect(report.contains('mailto'), isFalse);
    final screen = code(File(view));
    expect(screen.contains('mailto'), isFalse);
    // Sharing happens only from the sheet's own button.
    expect('_shareReport('.allMatches(screen).length, 2);
  });

  test('the catalogue holds no invented support address or credentials', () {
    final catalogue = code(File('$models/uae_links_catalogue.dart'));
    expect(catalogue.contains('@'), isFalse);
    expect(
        RegExp(r'password|secret|apikey', caseSensitive: false)
            .hasMatch(catalogue),
        isFalse);
  });
}
