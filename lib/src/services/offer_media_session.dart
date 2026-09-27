import 'package:flutter/foundation.dart';

import 'package:broker_wallet/src/services/offer_media_upload_queue.dart';
import 'package:broker_wallet/src/services/offer_media_url_cache.dart';

/// Keeps Offer media's account-scoped runtime state in step with the
/// application session.
///
/// Fed by `AuthViewModel`, whose every auth-state snapshot passes through one
/// place. Uploads run only for an application-authenticated account — never
/// for a password-recovery session and never for a session held in the
/// account-deletion quarantine, both of which are deliberately not
/// application-authenticated — and signed URLs never outlive the account
/// they were issued to.
abstract final class OfferMediaSession {
  static String? _owner;

  /// [uid] is the session's account; [active] says whether that session is
  /// application-authenticated right now.
  static void onAuthState({required String? uid, required bool active}) {
    final owner = active && uid != null && uid.isNotEmpty ? uid : null;
    if (owner == _owner) return;
    final previous = _owner;
    _owner = owner;
    if (previous != null) OfferMediaUrlCache.instance.clear();
    try {
      OfferMediaUploadQueue.instance.setActiveOwner(owner);
    } catch (_) {
      // The session must never fail because media could not follow it.
    }
  }

  @visibleForTesting
  static String? get activeOwner => _owner;

  @visibleForTesting
  static void reset() => _owner = null;
}
