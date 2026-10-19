/// Decides whether a directory address may be opened.
///
/// Government sign-in happens in the phone's own browser, so the app must never
/// be talked into opening anything but a plain HTTPS address on a domain the
/// catalogue was verified against. The match is on whole domain labels, so
/// `gov.ae.example.com` and `notgov.ae` are not `gov.ae`.
abstract final class UaeLinkUrlPolicy {
  /// The domains the verified catalogue lives on. Adding one is a deliberate
  /// edit that comes with its verification evidence.
  static const List<String> officialDomains = [
    'gov.ae',
    'u.ae',
    'uaepass.ae',
    'tamm.abudhabi',
    'dari.ae',
    'sharjah.ae',
    'ajman.ae',
    'rak.ae',
    'uaq.ae',
    'fujairah.ae',
    'digitaluaq.ae',
    'etihadwe.ae',
    // The one payment platform, labelled as a payment platform.
    'noqodi.com',
  ];

  static final RegExp _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');

  /// The address as a [Uri] when it is safe to open, otherwise null.
  static Uri? parse(String? raw) {
    if (raw == null) return null;
    final text = raw.trim();
    if (text.isEmpty || text.runes.any(_isUnsafeRune)) return null;
    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme) return null;
    if (uri.scheme != 'https') return null;
    if (uri.userInfo.isNotEmpty) return null;
    if (uri.hasPort && uri.port != 443) return null;
    final host = uri.host.toLowerCase();
    if (host.isEmpty || host.endsWith('.') || _ipv4.hasMatch(host)) {
      return null;
    }
    // A look-alike written in another script or with homoglyphs.
    if (host.split('.').any((label) => label.startsWith('xn--'))) return null;
    if (!isOfficialHost(host)) return null;
    return uri;
  }

  static bool isSafe(String? raw) => parse(raw) != null;

  /// Whitespace, control characters and backslashes never belong in an address.
  static bool _isUnsafeRune(int rune) =>
      rune <= 0x20 || (rune >= 0x7F && rune <= 0xA0) || rune == 0x5C;

  /// Whether [host] is an official domain or a sub-domain of one.
  static bool isOfficialHost(String host) {
    final lower = host.toLowerCase();
    for (final domain in officialDomains) {
      if (lower == domain || lower.endsWith('.$domain')) return true;
    }
    return false;
  }
}
