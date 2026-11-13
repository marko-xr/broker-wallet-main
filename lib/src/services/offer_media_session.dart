import 'package:flutter/foundation.dart';

import 'package:broker_wallet/src/services/app_access_policy.dart';
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
///
/// OFF-2b-2: the upload queue also runs only while the access policy is
/// online. In offline read-only mode it is paused at once (its tasks stay on
/// the phone) and no auth event can restart it; only the coordinator returning
/// the app to online resumes it. The account identity itself ([_owner]) does
/// not depend on the policy: held private media stays bound to the account.
abstract final class OfferMediaSession {
  static String? _owner;
  static String? _queueOwner;
  static bool _listening = false;

  /// [uid] is the session's account; [active] says whether that session is
  /// application-authenticated right now.
  static void onAuthState({required String? uid, required bool active}) {
    if (!_listening) {
      _listening = true;
      AppAccessPolicy.addListener(_onAccessMode);
    }
    final owner = active && uid != null && uid.isNotEmpty ? uid : null;
    if (owner != _owner) {
      final previous = _owner;
      _owner = owner;
      if (previous != null) OfferMediaUrlCache.instance.clear();
    }
    _syncQueue();
  }

  static void _onAccessMode(AppAccessMode mode) {
    // Signed links are transport; none is kept while nothing may be fetched.
    if (mode == AppAccessMode.offlineReadOnly) {
      OfferMediaUrlCache.instance.clear();
    }
    _syncQueue();
  }

  static void _syncQueue() {
    final owner = AppAccessPolicy.isOnline ? _owner : null;
    if (owner == _queueOwner) return;
    _queueOwner = owner;
    try {
      OfferMediaUploadQueue.instance.setActiveOwner(owner);
    } catch (_) {
      // The session must never fail because media could not follow it.
    }
  }

  /// The application-authenticated account now, or null. Read-only; the
  /// private image cache reads it to bind every read to this session.
  static String? get applicationAccount => _owner;

  @visibleForTesting
  static String? get activeOwner => _owner;

  /// The account the upload queue runs for now (null while paused).
  @visibleForTesting
  static String? get queueOwner => _queueOwner;

  @visibleForTesting
  static void reset() {
    _owner = null;
    _queueOwner = null;
    _listening = false;
  }
}
