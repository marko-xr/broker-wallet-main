import 'package:shared_preferences/shared_preferences.dart';

/// Remembers, across process death, that the stored Supabase session is a
/// password-recovery session and not an ordinary one.
///
/// ## Why this has to exist
///
/// A recovery session is only distinguishable from a normal session at one
/// moment: `AuthChangeEvent.passwordRecovery`, emitted when GoTrue exchanges
/// the recovery link. Nothing about the session itself records it. When the OS
/// kills the app and the user reopens it, `GoTrueClient.recoverSession`
/// restores the same tokens and emits `AuthChangeEvent.initialSession`, so the
/// restored recovery session is indistinguishable from a normal one and the app
/// would bootstrap straight into Home with a session that exists solely to set
/// a password. This store closes that hole.
///
/// ## Why it is safe to persist
///
/// It holds one value: the account id the recovery belongs to. No token, no
/// password, no email, no timestamp, and it is never used to *classify* a
/// callback — that is decided by the callback address. It only answers "is the
/// session currently in storage a recovery session", and it is bound to a uid
/// so it can never be inherited by a different account.
///
/// ## Stale-state analysis
///
/// The failure mode worth caring about is a marker that outlives its recovery
/// and locks a user out of their own app. Every exit from recovery clears it:
/// a completed reset, a cancellation, a sign-out, and any ordinary sign-in.
/// It is also ignored whenever the live session's uid does not match. So the
/// worst reachable state is a marker for the account that is signed in, with
/// no recovery in progress, which presents as the reset screen and is cleared
/// by the cancel action already on that screen — one extra tap, never a
/// lockout, and never silent access to the app.
///
/// The read path is deliberately synchronous after [prime]: the router has to
/// know before the first frame, and an asynchronous read would reintroduce the
/// very race this exists to remove.
abstract final class PasswordRecoveryStateStore {
  static const String _key = 'password_recovery_owner_uid';

  static String? _cachedUid;
  static bool _primed = false;

  /// Loads the persisted marker into memory. Called once during startup,
  /// before the auth pipeline can publish an identity.
  static Future<void> prime() async {
    if (_primed) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _cachedUid = prefs.getString(_key);
    } catch (_) {
      _cachedUid = null;
    }
    _primed = true;
  }

  /// The account a persisted recovery belongs to, or null. Synchronous by
  /// design; valid only after [prime].
  static String? get ownerUid => _cachedUid;

  static Future<void> remember(String uid) async {
    _cachedUid = uid;
    _primed = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, uid);
    } catch (_) {
      // The in-memory value still guards this run.
    }
  }

  static Future<void> forget() async {
    _cachedUid = null;
    _primed = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {
      // Clearing is best effort; the in-memory value is already gone.
    }
  }

  /// Test seam: resets both the cache and the primed flag.
  static void resetForTesting({String? ownerUid}) {
    _cachedUid = ownerUid;
    _primed = true;
  }
}
