import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/repositories/supabase_auth_repository.dart';
import 'package:broker_wallet/src/repositories/supabase_user_repository.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/login_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/signup_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _uid = '550e8400-e29b-41d4-a716-446655440000';

const _revokeMigration =
    'supabase/migrations/20260911000100_revoke_client_profile_phone_writes.sql';
const _guardMigration =
    'supabase/migrations/20260911000200_guard_pending_phone_changes.sql';
const _pgTapSuite = 'supabase/tests/phone_security_test.sql';
const _validationScript = 'supabase/validation/phone_security_validation.sql';

String _read(String path) => File(path).readAsStringSync();

/// SQL without comments, so assertions are about statements, not prose.
String _sqlStatements(String path) => _read(path)
    .split('\n')
    .map((line) {
      final comment = line.indexOf('--');
      return comment >= 0 ? line.substring(0, comment) : line;
    })
    .join('\n')
    .toLowerCase();

String _fakeJwt() {
  String part(Map<String, dynamic> v) =>
      base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
  final exp = DateTime.now().add(const Duration(hours: 1));
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({'sub': _uid, 'exp': exp.millisecondsSinceEpoch ~/ 1000})}.sig';
}

/// A signed-in SupabaseClient on a recorded transport.
class _Backend {
  final List<http.Request> requests = [];

  late final sb.SupabaseClient client = sb.SupabaseClient(
    'https://unit-test.supabase.co',
    'unit-test-publishable-key',
    httpClient: MockClient((request) async {
      requests.add(request);
      // PostgREST reads the originating request back off the response.
      if (request.method == 'PATCH' &&
          request.url.path.endsWith('/rest/v1/profiles')) {
        return http.Response(
          jsonEncode({'name': 'Saved Name'}),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }
      return http.Response('[]', 200,
          headers: {'content-type': 'application/json'}, request: request);
    }),
    authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
  );

  Future<void> signIn() => client.auth.setInitialSession(jsonEncode({
        'access_token': _fakeJwt(),
        'token_type': 'bearer',
        'expires_in': 3600,
        'expires_at': DateTime.now()
                .add(const Duration(hours: 1))
                .millisecondsSinceEpoch ~/
            1000,
        'refresh_token': 'refresh',
        'user': {
          'id': _uid,
          'aud': 'authenticated',
          'email': 'phone@example.test',
          'app_metadata': {'provider': 'email'},
          'user_metadata': <String, dynamic>{},
          'created_at': '2026-09-11T10:00:00Z',
        },
      }));

  Iterable<http.Request> get profileWrites => requests.where((r) =>
      r.method == 'PATCH' && r.url.path.endsWith('/rest/v1/profiles'));
}

class _NoProfiles implements UserRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

UserModel _user({String? phone}) => UserModel(
      uid: _uid,
      name: 'Phone User',
      email: 'phone@example.test',
      phoneNumber: phone,
      createdAt: DateTime(2026, 9, 11),
      isEmailVerified: true,
      isPhoneVerified: phone != null,
      subscription:
          UserSubscription(plan: 'test', isActive: false, features: const []),
      preferences: const {'notificationsEnabled': true},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Profile phone mirror grants (migration)', () {
    test('clients lose UPDATE on phone_number and phone_e164', () {
      final sql = _sqlStatements(_revokeMigration);
      expect(
        sql,
        contains('revoke update (phone_number, phone_e164) on public.profiles '
            'from authenticated'),
      );
      // Nothing else is widened or narrowed.
      expect(sql, isNot(contains('grant ')));
      expect(sql, isNot(contains('is_phone_verified')));
    });

    test('the revoke runs after the grant it narrows and the sync it relies on',
        () {
      final migrations = Directory('supabase/migrations')
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .toList()
        ..sort();
      final revoke = migrations.indexOf(_revokeMigration.split('/').last);
      final guard = migrations.indexOf(_guardMigration.split('/').last);
      final baseline =
          migrations.indexOf('20260821000100_broker_wallet_baseline.sql');
      final sync = migrations
          .indexOf('20260822000400_sync_auth_identity_to_profiles.sql');

      expect(revoke, greaterThan(baseline));
      expect(revoke, greaterThan(sync));
      expect(guard, greaterThan(revoke));
    });

    test('the trusted sync that maintains the mirror runs as its owner', () {
      final sync =
          _sqlStatements('supabase/migrations/20260822000400_sync_auth_identity_to_profiles.sql');
      expect(sync, contains('security definer'));
      expect(sync, contains('phone_number = nullif(new.phone'));
      expect(sync, contains('is_phone_verified = new.phone_confirmed_at is not null'));
    });
  });

  group('Pending phone-change guard (migration)', () {
    late String sql;
    setUpAll(() => sql = _sqlStatements(_guardMigration));

    test('guards every phone_change write on auth.users', () {
      expect(
        sql,
        contains('before update of phone_change on auth.users'),
      );
      expect(sql, contains('execute function public.guard_pending_phone_change()'));
    });

    test('serializes concurrent requests for the same number', () {
      expect(sql, contains('pg_advisory_xact_lock('));
      // The lock is keyed by the pending number, taken before the checks.
      final lock = sql.indexOf('pg_advisory_xact_lock(');
      final check = sql.indexOf('if exists (');
      expect(lock, lessThan(check));
    });

    test('clears abandoned attempts using one bounded grace period', () {
      expect(sql, contains("interval '15 minutes'"));
      expect(
        'public.phone_change_grace_period()'.allMatches(sql).length,
        greaterThanOrEqualTo(2),
        reason: 'trigger and sweep share one definition',
      );
      expect(sql, contains("set phone_change = ''"));
    });

    test('refuses a second live pending holder or a number confirmed elsewhere',
        () {
      expect(sql, contains('phone_change = new.phone_change or phone = new.phone_change'));
      expect(sql, contains("message = 'phone_change_unavailable'"));
    });

    test('functions are hardened and not callable by clients', () {
      expect(
        'security definer'.allMatches(sql).length,
        greaterThanOrEqualTo(2),
      );
      expect("set search_path = ''".allMatches(sql).length,
          greaterThanOrEqualTo(3));
      for (final fn in const [
        'public.guard_pending_phone_change()',
        'public.clear_stale_phone_changes()',
      ]) {
        expect(sql, contains('revoke all on function $fn from authenticated'),
            reason: fn);
        expect(sql, contains('revoke all on function $fn from anon'),
            reason: fn);
      }
    });

    test('does not alter Supabase-managed auth schema objects', () {
      expect(sql, isNot(contains('alter table auth.')));
      expect(sql, isNot(contains('create unique index')));
      expect(sql, isNot(contains('create index')));
      expect(sql, isNot(contains('add constraint')));
      expect(sql, isNot(contains('create function auth.')));
      expect(sql, isNot(contains('create or replace function auth.')));
    });

    test('the periodic sweep is scheduled only when pg_cron exists', () {
      expect(sql, contains("where extname = 'pg_cron'"));
      expect(sql, contains("'clear-stale-phone-changes'"));
    });

    test('the database test suite declares exactly the checks it makes', () {
      final suite = _read(_pgTapSuite);
      final plan = int.parse(
          RegExp(r'select plan\((\d+)\)').firstMatch(suite)!.group(1)!);
      final assertions = RegExp(
        r'^select (ok|is|throws_ok|throws_like|lives_ok|has_trigger)\(',
        multiLine: true,
      ).allMatches(suite).length;
      expect(assertions, plan);
    });

    test('an unchanged re-save by Supabase Auth is never guarded', () {
      expect(
        RegExp(r'if new\.phone_change is not distinct from old\.phone_change\s+'
                r'and new\.phone_change_token is not distinct from old\.phone_change_token\s+'
                r'and new\.phone_change_sent_at is not distinct from old\.phone_change_sent_at\s+'
                r'then\s+return new;')
            .hasMatch(sql),
        isTrue,
      );
      // The skip comes before the lock and the checks.
      expect(
        sql.indexOf('is not distinct from old.phone_change'),
        lessThan(sql.indexOf('pg_advisory_xact_lock(')),
      );
    });

    test('stale cleanup never waits on another account row lock', () {
      final guard = sql.substring(
        sql.indexOf('function public.guard_pending_phone_change()'),
        sql.indexOf('create trigger guard_pending_phone_change'),
      );
      expect(guard, contains('for update skip locked'));
    });

    test('the grace period function is not callable by clients', () {
      for (final role in const ['public', 'anon', 'authenticated']) {
        expect(
          sql,
          contains(
              'revoke all on function public.phone_change_grace_period() from $role'),
          reason: role,
        );
      }
    });

    test('database re-sends change the token, as Supabase Auth does', () {
      // now() is fixed within a transaction; a re-send that only rewrites
      // now() would take the unchanged re-save path and never reach the guard.
      for (final path in const [_pgTapSuite, _validationScript]) {
        final resends = RegExp(
          r'set phone_change = phone_change,[^;]*phone_change_sent_at = now\(\)',
        ).allMatches(_read(path).replaceAll('\r\n', '\n'));
        expect(resends, isNotEmpty, reason: path);
        for (final resend in resends) {
          expect(resend.group(0), contains('phone_change_token = '),
              reason: path);
        }
      }
    });
  });

  group('Hosted validation script', () {
    late String script;
    setUpAll(() => script = _read(_validationScript).replaceAll('\r\n', '\n'));

    /// A migration as it must appear inside the script: its own transaction
    /// lines removed, blank-line runs collapsed, surrounding space trimmed.
    String normalized(String sql) => sql
        .replaceAll('\r\n', '\n')
        .split('\n')
        .map((line) => line.trimRight())
        .where((line) => line != 'begin;' && line != 'commit;')
        .join('\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();

    String embedded(String tag) {
      final quote = RegExp.escape('\$$tag\$');
      final match = RegExp('$quote\\n([\\s\\S]*?)$quote;').firstMatch(script);
      expect(match, isNotNull, reason: 'missing embedded $tag');
      return normalized(match!.group(1)!);
    }

    test('installs both migrations from their exact file text', () {
      expect(embedded('migration_20260911000100'),
          normalized(_read(_revokeMigration)));
      expect(embedded('migration_20260911000200'),
          normalized(_read(_guardMigration)));
    });

    test('opens one transaction, never commits, and ends by rolling back', () {
      final statements = script
          .split('\n')
          .where((line) => line.trim().isNotEmpty && !line.trim().startsWith('--'))
          .toList();
      expect(statements.first.trim(), 'begin;');
      expect(statements.last.trim(), 'rollback;');
      expect(
        RegExp(r'^\s*(commit|end\s+transaction)\s*;',
                multiLine: true, caseSensitive: false)
            .hasMatch(script),
        isFalse,
      );
      expect(
        RegExp(r'^\s*rollback\s*;', multiLine: true, caseSensitive: false)
            .allMatches(script),
        hasLength(1),
      );
    });

    test('undoes its own work before reporting and proves it', () {
      expect(script, contains("message = 'phone_validation_rollback'"));
      expect(script.indexOf("message = 'phone_validation_rollback'"),
          lessThan(script.indexOf('Post-checks')));
      for (final post in const [
        'post: the guard trigger is back to its state before the run',
        'post: the new functions are back to their state before the run',
        'post: the profile phone grants are back to their state before the run',
        'post: no test user or test profile remains',
        'post: this session no longer blocks Supabase Auth',
      ]) {
        expect(script, contains(post));
      }
    });

    test('touches only reserved test identities and bounds its locks', () {
      expect(script, contains("set local lock_timeout = '3s'"));
      expect(script, contains("set local statement_timeout = '60s'"));
      expect(script, contains("'@phone-validation.invalid'"));
      expect(
        RegExp(r"number_\w+ constant text := '(\d+)'")
            .allMatches(script)
            .map((m) => m.group(1)!),
        everyElement(startsWith('999')),
      );
      expect(script, contains('no real account has a phone change in progress'));
      expect(script, contains("carry only this project''s triggers"));
      // The only role it assumes is a signed-in client, and back.
      expect(
        RegExp(r'set (local |session )?role (\w+)', caseSensitive: false)
            .allMatches(script)
            .map((m) => m.group(2)!.toLowerCase())
            .toSet(),
        {'authenticated', 'none'},
      );
      expect(script.toLowerCase(), isNot(contains('create extension')));
    });

    test('covers the behavior the pgTAP suite covers', () {
      for (final check in const [
        'grants: authenticated cannot UPDATE profiles.phone_number or phone_e164',
        'client: a signed-in user cannot write its own profiles.phone_number',
        'client: a signed-in user cannot write its own profiles.phone_e164',
        'client: a signed-in user can still rename its own profile',
        'auth: a confirmed phone still syncs into the profile mirror',
        'trigger: guard_pending_phone_change is BEFORE UPDATE OF phone_change',
        'functions: anon and authenticated cannot EXECUTE any of the three',
        'guard: a second account cannot hold the same live pending number',
        'guard: the same account can request a new code for its own pending number',
        'guard: a stale attempt is cleared',
        'guard: a number confirmed on another account cannot become pending',
        'sweep: clears only the stale attempt',
        'auth: a sign-in style update that does not touch phone_change is unaffected',
        'auth: a full-row re-save with an unchanged pending change is never refused',
        'guard: resending a code for a number now confirmed elsewhere is refused',
        'guard: clearing a pending change neither recurses nor fails',
        'flow: confirming the change succeeds and reaches the profile as verified',
      ]) {
        expect(script, contains(check));
      }
    });
  });

  group('No client write to the profile phone mirror', () {
    test('profile saves send only name and preferences', () async {
      final backend = _Backend();
      await backend.signIn();
      final repository = SupabaseUserRepository(client: backend.client);

      await repository.updateUser(_user(phone: '+971501234567'));

      final body = jsonDecode(backend.profileWrites.single.body)
          as Map<String, dynamic>;
      expect(body.keys, unorderedEquals(['name', 'preferences']));
    });

    test('a phone passed to a profile save is refused, not written', () async {
      final backend = _Backend();
      await backend.signIn();
      final repository = SupabaseAuthRepository(
        userRepository: _NoProfiles(),
        client: backend.client,
      );

      await expectLater(
        repository.updateUserProfile(
          name: 'Name',
          phoneNumber: '+971501234567',
        ),
        throwsA(isA<AuthFailure>().having(
            (f) => f.code, 'code', AuthFailureCode.operationNotAllowed)),
      );
      expect(backend.requests, isEmpty);
    });

    test('a name save still writes the name alone', () async {
      final backend = _Backend();
      await backend.signIn();
      final repository = SupabaseAuthRepository(
        userRepository: _NoProfiles(),
        client: backend.client,
      );

      await repository.updateUserProfile(name: 'Saved Name');

      final body = jsonDecode(backend.profileWrites.single.body)
          as Map<String, dynamic>;
      expect(body, {'name': 'Saved Name'});
    });

    test('Supabase write paths contain no profile phone column keys', () {
      final userRepository =
          _read('lib/src/repositories/supabase_user_repository.dart');
      expect(userRepository, isNot(contains("'phone_number':")));
      expect(userRepository, isNot(contains("'phone_e164':")));

      final authRepository =
          _read('lib/src/repositories/supabase_auth_repository.dart');
      expect(authRepository, isNot(contains('phone_e164')));
      // The only 'phone_number' key left is sign-up user metadata sent to
      // Supabase Auth — not a profiles column write.
      final keys = "'phone_number':".allMatches(authRepository).length;
      expect(keys, 1);
      final metadata = authRepository.indexOf('data: {');
      final key = authRepository.indexOf("'phone_number':");
      expect(key, greaterThan(metadata));
      expect(key - metadata, lessThan(300));
    });

    test('the legacy profile save sends no phone in Supabase mode', () {
      final source = _read('lib/src/viewmodels/edit_profile_viewmodel.dart');
      expect(
        source,
        contains(
            'phoneNumber: SupabaseConfig.useSupabaseAuth ? null : sanitizedPhone'),
      );
    });
  });

  group('Sign-in and sign-up offer no dead-end phone option', () {
    test('login defaults to email and cannot switch to phone', () {
      expect(SignInViewModel.phoneSignInAvailable, isFalse);
      expect(SignInViewModel.initialLoginMethod, LoginMethod.email);

      final vm = SignInViewModel();
      expect(vm.loginMethod, LoginMethod.email);
      vm.setLoginMethod(LoginMethod.phone);
      expect(vm.loginMethod, LoginMethod.email);
      vm.dispose();
    });

    test('sign-up defaults to email and cannot switch to phone', () {
      expect(SignUpViewModel.phoneSignUpAvailable, isFalse);
      expect(SignUpViewModel.initialSignupMethod, SignupMethod.email);

      final vm = SignUpViewModel();
      expect(vm.signupMethod, SignupMethod.email);
      vm.setSignupMethod(SignupMethod.phone);
      expect(vm.signupMethod, SignupMethod.email);
      vm.dispose();
    });

    test('the phone tabs render only where phone sign-in exists', () {
      final login = _read('lib/src/views/Screens/Sign-Up-Log-In/login_view.dart');
      final loginGate = login.indexOf('if (SignInViewModel.phoneSignInAvailable)');
      expect(loginGate, isNonNegative);
      expect(login.indexOf('_LoginTabs(', loginGate), greaterThan(loginGate));
      expect(login.indexOf('_LoginTabs('), greaterThan(loginGate),
          reason: 'no ungated tab bar');

      final signup =
          _read('lib/src/views/Screens/Sign-Up-Log-In/signup_view.dart');
      final signupGate =
          signup.indexOf('if (SignUpViewModel.phoneSignUpAvailable)');
      expect(signupGate, isNonNegative);
      expect(signup.indexOf('_SignupTabs('), greaterThan(signupGate),
          reason: 'no ungated tab bar');
    });
  });
}
