// Manual, owner-driven cross-account RLS probe for `public.offices`.
//
// This test never signs anyone in, never extracts a credential, and never
// prints anything identity- or content-bearing. It boots the real,
// unmodified application and then waits — with a bounded timeout, not an
// unbounded pumpAndSettle loop — for a human to sign in through the app's
// own existing Sign In screen: first as Account A, then (after manually
// signing out) as Account B. It reads only `id` for one Office row supplied
// at runtime via --dart-define (never hard-coded, never committed), issues
// that query with NO client-side `owner_id` filter (the point is to exercise
// the server-side RLS policy itself, not the app's own ownership scoping),
// and asserts a row count. Nothing about the record's other columns, the
// authenticated user id, or any credential is ever read, printed, or
// persisted by this file.
//
// This file is not imported by anything under lib/ and is never part of a
// release build: `integration_test/` is its own separate build target,
// invoked only via `flutter test integration_test/<file> -d <device>`.
//
// NOT RUN as part of this checkpoint. Do not execute without separate,
// explicit owner approval — see the accompanying report for the device-data
// risk this specific run carries and the safer alternative device options.

import 'package:broker_wallet/main.dart' as app;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Wraps a Supabase user id for in-memory equality comparison only. Its
/// `toString()` is deliberately redacted so that even an incidental use in a
/// framework-generated failure message (which this file never triggers
/// intentionally) cannot leak the underlying id.
class _Identity {
  const _Identity._(this._uid);

  factory _Identity.fromUid(String uid) => _Identity._(uid);

  final String _uid;

  @override
  bool operator ==(Object other) => other is _Identity && other._uid == _uid;

  @override
  int get hashCode => _uid.hashCode;

  @override
  String toString() => '<redacted-identity>';
}

/// Reads the live app's own Supabase client's current user, if any. Returns
/// null both when no session is signed in yet AND when `Supabase.instance`
/// itself is not reachable yet — `app.main()`'s own bootstrap
/// (`SupabaseBootstrapService.initialize()`) is a real, network-bound async
/// call that may not have completed by the time polling starts, and
/// `Supabase.instance` throws (rather than returning null) until it has.
/// Treating that as "not signed in yet" keeps the poll loop retrying instead
/// of crashing the test on an unrelated startup race.
User? _currentUserOrNull() {
  try {
    return Supabase.instance.client.auth.currentUser;
  } catch (_) {
    return null;
  }
}

/// Polls the live app's own Supabase client for a signed-in session. Never
/// touches credentials; only reads the already-live `auth.currentUser`.
Future<_Identity?> _waitForAuthenticatedSession({
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final user = _currentUserOrNull();
    if (user != null) {
      return _Identity.fromUid(user.id);
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  return null;
}

/// Polls until the live session's identity differs from [previousIdentity].
Future<_Identity?> _waitForDifferentAuthenticatedSession({
  required _Identity previousIdentity,
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final user = _currentUserOrNull();
    if (user != null) {
      final candidate = _Identity.fromUid(user.id);
      if (candidate != previousIdentity) {
        return candidate;
      }
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  return null;
}

/// Issues the direct, unfiltered-by-owner Office SELECT. Returns null (never
/// the raw exception, which could embed request/response detail) on any
/// failure so the caller can treat it as inconclusive rather than a result.
Future<List<Map<String, dynamic>>?> _selectOfficeIdDirect(
  String officeId,
) async {
  try {
    // Deliberately no `.eq('owner_id', ...)`: this must exercise the
    // server-side RLS policy itself, not the application's usual
    // client-side ownership scoping (see SupabaseCoreEntitiesService).
    final rows = await Supabase.instance.client
        .from('offices')
        .select('id')
        .eq('id', officeId);
    return rows;
  } catch (_) {
    return null;
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Without this, the binding only repaints the device screen on an
  // explicit tester.pump() call — it does not behave like a normally
  // running app that keeps rendering on its own. This test pumps once at
  // startup and then only does Future.delayed-based waiting for the rest
  // of both manual auth phases, so without `fullyLive` the screen freezes
  // on whatever frame was showing at that one pump (observed on-device as
  // a stuck "Test starting..." placeholder) even though the app's real
  // async logic underneath keeps running and completing correctly. This
  // makes the device screen behave like an ordinary running app for the
  // whole test, so the owner can actually see and use the Sign In screen
  // during both manual phases.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  // fullyLive fixes rendering only: by default LiveTestWidgetsFlutterBinding
  // still intercepts real device pointer events for its own finder
  // diagnostics instead of delivering them to the running app. This is what
  // lets the owner's actual physical taps (e.g. on Profile/BottomNavBar)
  // reach the app during both manual auth phases.
  binding.shouldPropagateDevicePointerEvents = true;

  testWidgets(
    'cross-account Office RLS probe (manual, owner-driven, SELECT-only)',
    (tester) async {
      const officeId = String.fromEnvironment('RLS_PROBE_OFFICE_ID');
      expect(
        officeId.isNotEmpty,
        isTrue,
        reason: 'Pass --dart-define=RLS_PROBE_OFFICE_ID=<uuid> at run time. '
            'This test intentionally has no hard-coded record id.',
      );

      app.main();
      await tester.pump(const Duration(seconds: 2));

      // --- Phase A: Account A signs in manually; positive control -------
      final identityA = await _waitForAuthenticatedSession(
        timeout: const Duration(minutes: 5),
      );
      expect(
        identityA,
        isNotNull,
        reason: 'Timed out waiting for Account A to sign in through the '
            "app's normal Sign In screen.",
      );

      final rowsAsA = await _selectOfficeIdDirect(officeId);
      expect(
        rowsAsA,
        isNotNull,
        reason: 'The Office query as Account A failed to execute.',
      );
      expect(
        rowsAsA!.length,
        1,
        reason: 'Account A must see exactly one row for its own Office '
            'record before the negative phase is meaningful. '
            'Row count: ${rowsAsA.length}.',
      );

      // Only reached once Account A's positive control has actually
      // succeeded (both expect() calls above completed without throwing).
      // Non-sensitive: no account id, record id, fingerprint, token, or
      // response body — just a fixed, greppable signal string.
      debugPrint('OFFICE_RLS_A_PASS — SIGN OUT AND SIGN IN AS ACCOUNT B');

      // --- Manual transition: owner signs out of A, signs in as B -------
      final identityB = await _waitForDifferentAuthenticatedSession(
        previousIdentity: identityA!,
        timeout: const Duration(minutes: 5),
      );
      expect(
        identityB,
        isNotNull,
        reason: 'Timed out waiting for Account B to sign in, or the '
            'session never actually changed from Account A.',
      );

      // --- Phase B: Account B, negative control --------------------------
      final rowsAsB = await _selectOfficeIdDirect(officeId);
      expect(
        rowsAsB,
        isNotNull,
        reason: 'The Office query as Account B failed to execute.',
      );
      expect(
        rowsAsB!.length,
        0,
        reason: 'SECURITY: Account B received a non-empty result for an '
            'Office row it does not own. Row count: ${rowsAsB.length}.',
      );
    },
    // The two manual-wait phases are each bounded at up to 5 minutes, so
    // their sum alone can reach 10 minutes before either produces its own
    // descriptive expect() failure. This outer timeout must stay
    // comfortably above that sum plus app boot and the two real network
    // round trips, so a legitimate slow run fails with this file's own
    // attributable reason rather than a generic framework timeout cutting
    // it off mid-phase.
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
