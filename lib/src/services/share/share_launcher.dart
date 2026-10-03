import 'package:broker_wallet/src/services/share/share_models.dart';

/// The platform's share sheet. The only place a share leaves the app, kept
/// behind an interface so everything before it can be exercised without a phone.
abstract interface class ShareSink {
  /// Opens the share sheet and completes when it is closed. May throw.
  Future<ShareOutcome> send(ShareRequest request);
}

/// Opens the native share sheet, one at a time.
///
/// A second share asked for while a sheet is open is ignored rather than
/// stacked: Android would cancel the first one, and two sheets are never what
/// anyone meant by a double tap. A share with nothing in it is never opened.
/// Whatever the platform throws is reduced to a [ShareFailure] with no text from
/// the platform in it.
class ShareLauncher {
  ShareLauncher(this._sink);

  final ShareSink _sink;
  bool _open = false;

  /// Whether a share sheet is open right now.
  bool get isOpen => _open;

  /// Opens the sheet for [request]. Returns null, without opening anything, when
  /// a sheet is already open. Throws a [ShareFailure] when the sheet could not
  /// be opened or the request has no content.
  Future<ShareOutcome?> launch(ShareRequest request) async {
    if (!request.hasContent) {
      throw const ShareFailure(ShareFailureKind.generic);
    }
    if (_open) return null;
    _open = true;
    try {
      return await _sink.send(request);
    } on ShareFailure {
      rethrow;
    } catch (_) {
      throw const ShareFailure(ShareFailureKind.generic);
    } finally {
      _open = false;
    }
  }
}
