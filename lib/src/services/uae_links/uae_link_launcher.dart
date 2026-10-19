import 'package:url_launcher/url_launcher.dart';

import 'package:broker_wallet/src/services/uae_links/uae_link_url_policy.dart';

enum UaeLinkOpenResult {
  /// The system accepted the request to open the page. It says nothing about
  /// what the user then did on the site.
  opened,

  /// The address failed the safety policy and was never handed to the system.
  rejected,

  /// No browser accepted it, or the platform threw.
  failed,
}

/// Opens a directory address in the phone's own browser.
///
/// Nothing is appended to the address (no user id, no token), and a result of
/// [UaeLinkOpenResult.opened] is returned only when the platform reported that
/// it launched the page.
class UaeLinkLauncher {
  const UaeLinkLauncher({Future<bool> Function(Uri uri)? launch})
      : _launch = launch;

  final Future<bool> Function(Uri uri)? _launch;

  Future<UaeLinkOpenResult> open(String url) async {
    final uri = UaeLinkUrlPolicy.parse(url);
    if (uri == null) return UaeLinkOpenResult.rejected;
    try {
      final launch = _launch ?? _launchExternally;
      return await launch(uri)
          ? UaeLinkOpenResult.opened
          : UaeLinkOpenResult.failed;
    } catch (_) {
      // A missing browser can throw on some platforms.
      return UaeLinkOpenResult.failed;
    }
  }

  static Future<bool> _launchExternally(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);
}
