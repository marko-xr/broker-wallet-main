import 'package:flutter/widgets.dart';

export 'tap_card_host_stub.dart'
    if (dart.library.js_interop) 'tap_card_host_web.dart';

/// What Tap's card component is drawn with.
@immutable
class TapCardConfig {
  const TapCardConfig({
    required this.publicKey,
    required this.amount,
    required this.currency,
    required this.arabic,
    required this.dark,
  });

  final String publicKey;
  final double amount;
  final String currency;
  final bool arabic;
  final bool dark;
}

/// Tap's own card component. Card data stays inside it: this app only ever
/// receives a one-time `tok_` token.
abstract interface class TapCardHost {
  Widget view();

  Future<void> mount(
    TapCardConfig config, {
    required VoidCallback onReady,
    required ValueChanged<bool> onValidity,
    required VoidCallback onFailure,
  });

  /// A one-time token for the entered card.
  Future<String> tokenize();

  void dispose();
}
