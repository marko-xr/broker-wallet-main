// Delete Account for phone accounts (C4, Model X): the code sent to the
// account's own sign-in number replaces the password; the password path for
// email accounts is unchanged.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/themes/app_theme.dart';
import 'package:broker_wallet/src/services/account_deletion_service.dart';
import 'package:broker_wallet/src/viewmodels/delete_account_viewmodel.dart';
import 'package:broker_wallet/src/views/Widgets/delete_account_sheet.dart';
import 'package:broker_wallet/src/views/Widgets/otp_code_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _pat = '33333333-3333-4333-8333-333333333333';
const _other = '44444444-4444-4444-8444-444444444444';
const _phone = '+971501111111';
const _code = '123456';

class _Session implements AccountDeletionSession {
  @override
  String? currentUserId = _pat;

  @override
  bool isPasswordRecoveryActive = false;

  final List<String> completed = [];
  final List<String> reconciled = [];
  AccountDeletionConvergence convergence = AccountDeletionConvergence.none;

  @override
  Future<void> completeAccountDeletion(String deletedUid) async {
    completed.add(deletedUid);
  }

  @override
  Future<AccountDeletionConvergence> reconcileAccountDeletion(
      String uid) async {
    reconciled.add(uid);
    return convergence;
  }
}

class _Markers extends AccountDeletionMarkers {
  final List<String> remembered = [];
  final List<String> forgotten = [];

  @override
  Future<void> remember(String uid) async => remembered.add(uid);

  @override
  Future<void> forgetIfOwnedBy(String uid) async => forgotten.add(uid);
}

/// Both proofs, recorded.
class _Gateway implements AccountDeletionGateway, PhoneAccountDeletionGateway {
  final List<String> codeRequests = [];
  final List<(String, String)> codeDeletes = [];
  final List<(String, String)> passwordDeletes = [];
  AccountDeletionFailure? requestFails;
  AccountDeletionFailure? deleteFails;
  Completer<void>? hold;

  @override
  Future<void> requestDeletionCode({required String expectedUid}) async {
    codeRequests.add(expectedUid);
    if (requestFails != null) throw requestFails!;
  }

  @override
  Future<void> deleteAccountWithCode({
    required String expectedUid,
    required String code,
  }) async {
    codeDeletes.add((expectedUid, code));
    if (hold != null) await hold!.future;
    if (deleteFails != null) throw deleteFails!;
  }

  @override
  Future<void> deleteAccount({
    required String expectedUid,
    required String password,
  }) async {
    passwordDeletes.add((expectedUid, password));
    if (deleteFails != null) throw deleteFails!;
  }
}

/// A gateway that only knows the password path.
class _PasswordOnlyGateway implements AccountDeletionGateway {
  @override
  Future<void> deleteAccount({
    required String expectedUid,
    required String password,
  }) async {}
}

DeleteAccountViewModel _vm(
  _Gateway gateway,
  _Session session, {
  _Markers? markers,
  String? phone = _phone,
  bool withEmail = false,
}) =>
    DeleteAccountViewModel(
      gateway: gateway,
      session: session,
      markers: markers ?? _Markers(),
      signInPhoneE164: phone,
      canUsePassword: withEmail,
    );

Future<DeleteAccountViewModel> _atCodeStep(
  _Gateway gateway,
  _Session session, {
  _Markers? markers,
  bool withEmail = false,
}) async {
  final vm = _vm(gateway, session, markers: markers, withEmail: withEmail);
  vm.continueToConfirmation();
  vm.setAcknowledged(true);
  expect(await vm.requestCode(), isTrue);
  return vm;
}

/// Bounded frames: a focused code field keeps its cursor blinking, so
/// pumpAndSettle would never return.
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic> en;
  late Map<String, dynamic> ar;

  setUpAll(() async {
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      (ByteData? message) async {
        final key = utf8.decode(message!.buffer.asUint8List());
        final file = File(key);
        if (!file.existsSync()) return null;
        final bytes = Uint8List.fromList(file.readAsBytesSync());
        return ByteData.view(bytes.buffer);
      },
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('PonnamKarthik/fluttertoast'),
      (call) async => true,
    );
    await AppLocalizations.preloadAllLanguages();
    en = json.decode(
      File('lib/src/common/localization/app_en.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
    ar = json.decode(
      File('lib/src/common/localization/app_ar.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
  });

  group('View model', () {
    test(
        'a phone account confirms with a code; an email account with its '
        'password', () {
      final phoneVm = _vm(_Gateway(), _Session());
      expect(phoneVm.proof, DeleteAccountProof.phoneCode);
      expect(phoneVm.canSwitchProof, isFalse);
      final emailVm = _vm(_Gateway(), _Session(), phone: null);
      expect(emailVm.proof, DeleteAccountProof.password);
      expect(emailVm.canSwitchProof, isFalse);
      final bothVm = _vm(_Gateway(), _Session(), withEmail: true);
      expect(bothVm.proof, DeleteAccountProof.phoneCode);
      expect(bothVm.canSwitchProof, isTrue);
    });

    test('the code is requested for the captured account only', () async {
      final gateway = _Gateway();
      final vm = await _atCodeStep(gateway, _Session());
      expect(gateway.codeRequests, [_pat]);
      expect(vm.codeSent, isTrue);
      expect(gateway.passwordDeletes, isEmpty);
    });

    test('local refusals reach no server', () async {
      final gateway = _Gateway();
      final session = _Session();
      final vm = _vm(gateway, session);
      vm.continueToConfirmation();

      expect(await vm.submitCode(code: _code), isFalse);
      expect(vm.errorKey, 'deleteAccountErrorAcknowledge');
      vm.setAcknowledged(true);
      expect(await vm.submitCode(code: _code), isFalse);
      expect(vm.errorKey, 'deleteAccountErrorCodeRequired',
          reason: 'no code was sent yet');
      await vm.requestCode();
      for (final bad in ['', '12345', '1234567', 'abcdef']) {
        expect(await vm.submitCode(code: bad), isFalse, reason: bad);
        expect(vm.errorKey, 'deleteAccountErrorCodeRequired', reason: bad);
      }
      expect(gateway.codeDeletes, isEmpty);
    });

    test('a valid code deletes the account and ends it locally', () async {
      final gateway = _Gateway();
      final session = _Session();
      final markers = _Markers();
      final vm = await _atCodeStep(gateway, session, markers: markers);
      expect(await vm.submitCode(code: ' $_code '), isTrue);
      expect(gateway.codeDeletes, [(_pat, _code)]);
      expect(markers.remembered, [_pat],
          reason:
              'offline access is revoked before the request, as for passwords');
      expect(session.completed, [_pat]);
      expect(vm.isCompleted, isTrue);
    });

    test('a wrong code deletes nothing and keeps the code step', () async {
      final gateway = _Gateway()
        ..deleteFails = const AccountDeletionFailure(
            AccountDeletionFailureCode.reauthenticationFailed);
      final markers = _Markers();
      final vm = await _atCodeStep(gateway, _Session(), markers: markers);
      expect(await vm.submitCode(code: _code), isFalse);
      expect(vm.errorKey, 'deleteAccountErrorCode');
      expect(vm.codeSent, isTrue, reason: 'the same code may be corrected');
      expect(vm.step, DeleteAccountStep.confirm);
      expect(markers.forgotten, [_pat]);
    });

    test('an expired or used code asks for a new one', () async {
      final gateway = _Gateway()
        ..deleteFails = const AccountDeletionFailure(
            AccountDeletionFailureCode.codeExpired);
      final vm = await _atCodeStep(gateway, _Session());
      expect(await vm.submitCode(code: _code), isFalse);
      expect(vm.errorKey, 'deleteAccountErrorCodeExpired');
      expect(vm.codeSent, isFalse);
      gateway.deleteFails = null;
      expect(await vm.requestCode(), isTrue);
      expect(await vm.submitCode(code: _code), isTrue);
    });

    test('an account switch after the flow opened sends nothing', () async {
      final gateway = _Gateway();
      final session = _Session();
      final vm = _vm(gateway, session);
      vm.continueToConfirmation();
      vm.setAcknowledged(true);
      session.currentUserId = _other;
      expect(await vm.requestCode(), isFalse);
      expect(vm.errorKey, 'deleteAccountErrorAccountChanged');
      expect(gateway.codeRequests, isEmpty);

      session.currentUserId = _pat;
      await vm.requestCode();
      session.currentUserId = _other;
      expect(await vm.submitCode(code: _code), isFalse);
      expect(vm.errorKey, 'deleteAccountErrorAccountChanged');
      expect(gateway.codeDeletes, isEmpty);
    });

    test('a password-recovery session cannot ask for a code', () async {
      final gateway = _Gateway();
      final session = _Session()..isPasswordRecoveryActive = true;
      final vm = _vm(gateway, session);
      vm.continueToConfirmation();
      expect(vm.step, DeleteAccountStep.review);
      expect(await vm.requestCode(), isFalse);
      expect(gateway.codeRequests, isEmpty);
    });

    test(
        'an unknown outcome is settled through Supabase Auth, as for '
        'passwords', () async {
      final gateway = _Gateway()
        ..deleteFails =
            const AccountDeletionFailure(AccountDeletionFailureCode.network);
      final session = _Session()
        ..convergence = AccountDeletionConvergence.deleted;
      final vm = await _atCodeStep(gateway, session);
      expect(await vm.submitCode(code: _code), isTrue);
      expect(session.reconciled, [_pat]);
    });

    test('a second tap while deleting sends nothing more', () async {
      final gateway = _Gateway()..hold = Completer<void>();
      final vm = await _atCodeStep(gateway, _Session());
      final first = vm.submitCode(code: _code);
      expect(await vm.submitCode(code: _code), isFalse);
      expect(await vm.requestCode(), isFalse);
      gateway.hold!.complete();
      expect(await first, isTrue);
      expect(gateway.codeDeletes, hasLength(1));
      expect(gateway.codeRequests, hasLength(1));
    });

    test('code request refusals are fixed, localized outcomes', () async {
      for (final entry in {
        AccountDeletionFailureCode.rateLimited: 'deleteAccountErrorRateLimited',
        AccountDeletionFailureCode.unavailable: 'deleteAccountErrorUnavailable',
        AccountDeletionFailureCode.reauthenticationUnsupported:
            'deleteAccountErrorUnsupported',
        AccountDeletionFailureCode.network: 'deleteAccountErrorNetwork',
      }.entries) {
        final gateway = _Gateway()
          ..requestFails = AccountDeletionFailure(entry.key);
        final vm = _vm(gateway, _Session());
        vm.continueToConfirmation();
        expect(await vm.requestCode(), isFalse);
        expect(vm.errorKey, entry.value, reason: entry.key.name);
        expect(vm.codeSent, isFalse);
      }
    });

    test('a phone account with an email may use its password instead',
        () async {
      final gateway = _Gateway();
      final session = _Session();
      final vm = _vm(gateway, session, withEmail: true);
      vm.continueToConfirmation();
      vm.setAcknowledged(true);
      vm.useProof(DeleteAccountProof.password);
      expect(vm.proof, DeleteAccountProof.password);
      expect(await vm.submit(password: 'Pam-Password-1'), isTrue);
      expect(gateway.passwordDeletes, [(_pat, 'Pam-Password-1')]);
      expect(gateway.codeRequests, isEmpty);
    });

    test('a phone account without an email cannot switch to a password', () {
      final vm = _vm(_Gateway(), _Session());
      vm.continueToConfirmation();
      vm.useProof(DeleteAccountProof.password);
      expect(vm.proof, DeleteAccountProof.phoneCode);
    });

    test('a backend without the phone path reports unavailable', () async {
      final vm = DeleteAccountViewModel(
        gateway: _PasswordOnlyGateway(),
        session: _Session(),
        markers: _Markers(),
        signInPhoneE164: _phone,
      );
      vm.continueToConfirmation();
      expect(await vm.requestCode(), isFalse);
      expect(vm.errorKey, 'deleteAccountErrorUnavailable');
    });

    test('every key the phone path can show exists in English and Arabic', () {
      final keys = {
        'deleteAccountCodeDescription',
        'deleteAccountSendCode',
        'deleteAccountUsePassword',
        'deleteAccountUseCode',
        'deleteAccountErrorCodeRequired',
        for (final code in AccountDeletionFailureCode.values) ...[
          deleteAccountErrorKey(code),
          deleteAccountErrorKey(code, proof: DeleteAccountProof.phoneCode),
        ],
      };
      for (final key in keys) {
        expect(en[key], isA<String>(), reason: 'en $key');
        expect(ar[key], isA<String>(), reason: 'ar $key');
        expect(ar[key], isNot(en[key]), reason: 'ar $key is translated');
      }
    });
  });

  group('Worker gateway', () {
    WorkerAccountDeletionGateway gatewayAnswering(
      List<http.Request> sent,
      http.Response Function(http.Request) answer, {
      String userId = _pat,
    }) =>
        WorkerAccountDeletionGateway(
          httpClient: MockClient((request) async {
            sent.add(request);
            return answer(request);
          }),
          readCredentials: () => AccountDeletionCredentials(
            userId: userId,
            accessToken: 'live-token',
          ),
        );

    test('the challenge sends only the live token: no number, no user id',
        () async {
      final sent = <http.Request>[];
      final gateway = gatewayAnswering(
          sent,
          (_) => http.Response(
              '{"status":"code_sent","expiresInSeconds":600}', 200));
      await gateway.requestDeletionCode(expectedUid: _pat);
      final request = sent.single;
      expect(request.url.path, '/account/delete/challenge');
      expect(request.headers['Authorization'], 'Bearer live-token');
      expect(json.decode(request.body), <String, Object?>{});
      expect(request.body.contains(_pat), isFalse);
    });

    test('deleting with a code sends only the code', () async {
      final sent = <http.Request>[];
      final gateway = gatewayAnswering(
          sent, (_) => http.Response('{"status":"deleted"}', 200));
      await gateway.deleteAccountWithCode(expectedUid: _pat, code: _code);
      final request = sent.single;
      expect(request.url.path, '/account/delete');
      expect(json.decode(request.body), {'code': _code});
    });

    test('a session that is no longer the expected account sends nothing',
        () async {
      final sent = <http.Request>[];
      final gateway = gatewayAnswering(sent, (_) => http.Response('{}', 200),
          userId: _other);
      await expectLater(
        gateway.requestDeletionCode(expectedUid: _pat),
        throwsA(isA<AccountDeletionFailure>().having(
            (f) => f.code, 'code', AccountDeletionFailureCode.accountChanged)),
      );
      await expectLater(
        gateway.deleteAccountWithCode(expectedUid: _pat, code: _code),
        throwsA(isA<AccountDeletionFailure>()),
      );
      expect(sent, isEmpty);
    });

    test('server codes map to fixed outcomes', () {
      AccountDeletionFailureCode challengeCode(int status, String body) {
        try {
          interpretDeletionChallengeResponse(status, body);
        } on AccountDeletionFailure catch (failure) {
          return failure.code;
        }
        fail('expected a failure');
      }

      AccountDeletionFailureCode deleteCode(int status, String body) {
        try {
          interpretAccountDeletionResponse(status, body);
        } on AccountDeletionFailure catch (failure) {
          return failure.code;
        }
        fail('expected a failure');
      }

      expect(challengeCode(409, '{"error":"reauthentication_unsupported"}'),
          AccountDeletionFailureCode.reauthenticationUnsupported);
      expect(challengeCode(429, '{"error":"rate_limited"}'),
          AccountDeletionFailureCode.rateLimited);
      expect(challengeCode(503, '{"error":"verification_unavailable"}'),
          AccountDeletionFailureCode.unavailable);
      expect(challengeCode(200, '{"status":"deleted"}'),
          AccountDeletionFailureCode.unknown,
          reason: 'only code_sent counts as sent');
      expect(deleteCode(409, '{"error":"challenge_required"}'),
          AccountDeletionFailureCode.codeExpired);
      expect(deleteCode(410, '{"error":"challenge_expired"}'),
          AccountDeletionFailureCode.codeExpired);
      expect(deleteCode(429, '{"error":"too_many_attempts"}'),
          AccountDeletionFailureCode.rateLimited);
      expect(deleteCode(403, '{"error":"reauthentication_failed"}'),
          AccountDeletionFailureCode.reauthenticationFailed);
      expect(accountDeletionNotAttempted,
          contains(AccountDeletionFailureCode.codeExpired));
    });
  });

  group('Sheet', () {
    Widget app(Widget child, {Locale locale = const Locale('en')}) =>
        MaterialApp(
          locale: locale,
          theme: AppTheme.lightTheme,
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(body: SingleChildScrollView(child: child)),
        );

    Future<void> openConfirm(
        WidgetTester tester, DeleteAccountViewModel vm) async {
      await tester
          .pumpWidget(app(DeleteAccountSheet(viewModel: vm, email: '')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en['deleteAccountContinue'] as String));
      await tester.pumpAndSettle();
    }

    FilledButton deleteButton(WidgetTester tester) =>
        tester.widget<FilledButton>(find.ancestor(
          of: find.text(en['deleteAccountConfirmButton'] as String),
          matching: find.byType(FilledButton),
        ));

    testWidgets('a phone account sends a code, enters it and deletes',
        (tester) async {
      final gateway = _Gateway();
      final vm = _vm(gateway, _Session());
      addTearDown(vm.dispose);
      await openConfirm(tester, vm);

      expect(find.text(en['deleteAccountCodeDescription'] as String),
          findsOneWidget);
      expect(find.text(_phone), findsOneWidget);
      expect(find.byType(OtpCodeField), findsNothing,
          reason: 'no code field before sending');
      expect(find.byType(TextField), findsNothing, reason: 'no password field');
      expect(find.text(en['deleteAccountUsePassword'] as String), findsNothing);
      expect(deleteButton(tester).onPressed, isNull);

      await tester.tap(find.text(en['deleteAccountSendCode'] as String));
      await _frames(tester);
      expect(gateway.codeRequests, [_pat]);
      expect(find.byType(OtpCodeField), findsOneWidget);

      await tester.enterText(find.byType(OtpCodeField), _code);
      await _frames(tester);
      expect(gateway.codeDeletes, isEmpty,
          reason:
              'a complete code (typed or autofilled) never deletes by itself');
      await tester.pump();
      expect(deleteButton(tester).onPressed, isNull,
          reason: 'the acknowledgement is still required');
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(deleteButton(tester).onPressed, isNotNull);

      await tester.tap(find.text(en['deleteAccountConfirmButton'] as String));
      await _frames(tester);
      expect(gateway.codeDeletes, [(_pat, _code)]);
      expect(vm.isCompleted, isTrue);
    });

    testWidgets('a wrong code is cleared and explained', (tester) async {
      final gateway = _Gateway()
        ..deleteFails = const AccountDeletionFailure(
            AccountDeletionFailureCode.reauthenticationFailed);
      final vm = _vm(gateway, _Session());
      addTearDown(vm.dispose);
      await openConfirm(tester, vm);
      await tester.tap(find.text(en['deleteAccountSendCode'] as String));
      await _frames(tester);
      await tester.enterText(find.byType(OtpCodeField), _code);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.text(en['deleteAccountConfirmButton'] as String));
      await _frames(tester);
      expect(find.text(en['deleteAccountErrorCode'] as String), findsOneWidget);
      expect(
          tester
              .widget<OtpCodeField>(find.byType(OtpCodeField))
              .controller
              .text,
          isEmpty);
      expect(vm.isCompleted, isFalse);
    });

    testWidgets('a phone account with an email can switch to its password',
        (tester) async {
      final gateway = _Gateway();
      final vm = _vm(gateway, _Session(), withEmail: true);
      addTearDown(vm.dispose);
      await openConfirm(tester, vm);
      await tester.tap(find.text(en['deleteAccountUsePassword'] as String));
      await tester.pumpAndSettle();
      expect(vm.proof, DeleteAccountProof.password);
      expect(find.text(en['deleteAccountUseCode'] as String), findsOneWidget);
      expect(find.text(en['deleteAccountSendCode'] as String), findsNothing);
    });

    testWidgets('an email account sees the unchanged password step',
        (tester) async {
      final vm = _vm(_Gateway(), _Session(), phone: null);
      addTearDown(vm.dispose);
      await openConfirm(tester, vm);
      expect(find.text(en['deleteAccountSendCode'] as String), findsNothing);
      expect(find.text(en['deleteAccountUseCode'] as String), findsNothing);
      expect(find.text(en['deleteAccountConfirmDescription'] as String),
          findsOneWidget);
    });

    testWidgets('Arabic renders the phone step without overflow',
        (tester) async {
      final vm = _vm(_Gateway(), _Session(), withEmail: true);
      addTearDown(vm.dispose);
      await tester.binding.setSurfaceSize(const Size(320, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app(DeleteAccountSheet(viewModel: vm, email: ''),
          locale: const Locale('ar')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(ar['deleteAccountContinue'] as String));
      await tester.pumpAndSettle();
      await tester.tap(find.text(ar['deleteAccountSendCode'] as String));
      await _frames(tester);
      expect(tester.takeException(), isNull);
      expect(find.text(ar['deleteAccountCodeDescription'] as String),
          findsOneWidget);
    });
  });
}
