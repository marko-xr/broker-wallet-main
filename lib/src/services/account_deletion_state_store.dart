import 'package:shared_preferences/shared_preferences.dart';

/// Remembers, across process death, that this device sent a deletion request
/// for an account and never learned how it ended.
///
/// A deletion can succeed on the server while its response is lost. The device
/// then still holds a session for an account that may no longer exist: its
/// access token keeps working locally until it expires, and nothing in the
/// session says the account is gone. While this marker names the account of a
/// newly applied session, `AuthViewModel` quarantines that session — it is
/// never application-authenticated — and ends it.
///
/// It holds one value, the account id the request was sent for. No token,
/// password, email or timestamp. It is only ever acted on for a session whose
/// id matches, and acting on it never deletes anything on a server.
///
/// The read path is synchronous after [prime], for the same reason as
/// `PasswordRecoveryStateStore`: the decision must be made in the same turn
/// the session identity is applied, or the router could see an authenticated
/// state first.
abstract final class AccountDeletionStateStore {
  static const String _key = 'account_deletion_pending_uid';

  static String? _cachedUid;
  static bool _primed = false;

  /// Loads the persisted marker into memory. Called once during startup,
  /// before the auth pipeline can publish an identity.
  static Future<void> prime() async {
    if (_primed) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_key);
      _cachedUid = (value ?? '').isEmpty ? null : value;
    } catch (_) {
      _cachedUid = null;
    }
    _primed = true;
  }

  /// The account a deletion of unknown outcome was sent for, or null.
  /// Synchronous by design; valid only after [prime].
  static String? get ownerUid => _cachedUid;

  static Future<void> remember(String uid) async {
    if (uid.isEmpty) return;
    _cachedUid = uid;
    _primed = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, uid);
    } catch (_) {
      // The in-memory value still guards this run.
    }
  }

  static Future<void> forgetIfOwnedBy(String uid) async {
    if (_cachedUid == uid) _cachedUid = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_key) == uid) await prefs.remove(_key);
    } catch (_) {
      // Best effort; the in-memory value is already gone.
    }
  }

  /// Test seam: sets the in-memory marker without touching storage.
  static void resetForTesting({String? ownerUid}) {
    _cachedUid = ownerUid;
    _primed = true;
  }
}
