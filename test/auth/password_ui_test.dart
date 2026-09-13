import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/services/auth_callback_coordinator.dart';
import 'package:broker_wallet/src/viewmodels/change_password_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/password_recovery_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/password_reset_request_viewmodel.dart';
import 'package:broker_wallet/src/views/Screens/Sign-Up-Log-In/reset_password_view.dart';
import 'package:broker_wallet/src/views/Widgets/change_password_sheet.dart';
import 'package:broker_wallet/src/views/Widgets/password_reset_request_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _uid = '550e8400-e29b-41d4-a716-446655440000';
const _validPassword = 'Passw0rdd';

class _Gateway implements PasswordCapability {
  _Gateway({this.verifiesCurrentPassword = false});

  @override
  final bool verifiesCurrentPassword;

  final StreamController<PasswordRecoverySession> _recovery =
      StreamController<PasswordRecoverySession>.broadcast();

  int changeCalls = 0;
  int resetCalls = 0;
  Object? failWith;

  @override
  Future<void> requestPasswordReset(String email) async {
    resetCalls++;
    if (failWith != null) throw failWith!;
  }

  @override
  Future<void> changePassword({
    required String newPassword,
    String? currentPassword,
  }) async {
    changeCalls++;
    if (failWith != null) throw failWith!;
  }

  @override
  Stream<PasswordRecoverySession> get passwordRecoverySessions =>
      _recovery.stream;

  bool recoveryActive = false;
  int recoveriesEnded = 0;

  @override
  bool get isPasswordRecoveryActive => recoveryActive;

  @override
  Future<void> endPasswordRecovery() async {
    recoveriesEnded++;
    recoveryActive = false;
  }

  void emit() => _recovery.add(
        PasswordRecoverySession(
          ownerUid: _uid,
          startedAt: DateTime.now().toUtc(),
        ),
      );

  Future<void> close() => _recovery.close();
}

class _Session implements AuthRepository {
  @override
  String? get currentUserId => _uid;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(Widget child, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: const [Locale('en'), Locale('ar')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, inner) => Directionality(
      textDirection:
          locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      child: inner ?? const SizedBox.shrink(),
    ),
    home: Scaffold(body: child),
  );
}

/// The English and Arabic strings the screens will actually render.
late final Map<String, dynamic> en;
late final Map<String, dynamic> ar;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Serve the ARB files from disk so these tests assert on the real
    // user-facing strings rather than on key names.
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
    await AppLocalizations.preloadAllLanguages();
    en = json.decode(
      File('lib/src/common/localization/app_en.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
    ar = json.decode(
      File('lib/src/common/localization/app_ar.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
  });

  group('Change password sheet', () {
    testWidgets(
        'asks for no current password when the backend will not '
        'verify one', (tester) async {
      final gateway = _Gateway();
      addTearDown(gateway.close);
      final vm = ChangePasswordViewModel(
        gateway: gateway,
        authRepository: _Session(),
      );
      addTearDown(vm.dispose);

      await tester.pumpWidget(_app(ChangePasswordSheet(viewModel: vm)));
      await tester.pumpAndSettle();

      expect(find.text(en['currentPassword'] as String), findsNothing);
      expect(find.text(en['newPassword'] as String), findsOneWidget);
      expect(find.text(en['confirmNewPassword'] as String), findsOneWidget);
    });

    testWidgets('asks for the current password when the backend verifies it',
        (tester) async {
      final gateway = _Gateway(verifiesCurrentPassword: true);
      addTearDown(gateway.close);
      final vm = ChangePasswordViewModel(
        gateway: gateway,
        authRepository: _Session(),
      );
      addTearDown(vm.dispose);

      await tester.pumpWidget(_app(ChangePasswordSheet(viewModel: vm)));
      await tester.pumpAndSettle();

      expect(find.text(en['currentPassword'] as String), findsOneWidget);
    });

    testWidgets('every password field starts obscured and can be revealed',
        (tester) async {
      final gateway = _Gateway();
      addTearDown(gateway.close);
      final vm = ChangePasswordViewModel(
        gateway: gateway,
        authRepository: _Session(),
      );
      addTearDown(vm.dispose);

      await tester.pumpWidget(_app(ChangePasswordSheet(viewModel: vm)));
      await tester.pumpAndSettle();

      final fields = tester.widgetList<TextField>(find.byType(TextField));
      expect(fields.length, 2);
      expect(fields.every((field) => field.obscureText), isTrue);

      await tester.tap(find.byIcon(Icons.visibility_outlined).first);
      await tester.pumpAndSettle();

      final revealed =
          tester.widgetList<TextField>(find.byType(TextField)).toList();
      expect(revealed.first.obscureText, isFalse);
      expect(revealed.last.obscureText, isTrue);
    });

    testWidgets('the requirement checklist reacts as the user types',
        (tester) async {
      final gateway = _Gateway();
      addTearDown(gateway.close);
      final vm = ChangePasswordViewModel(
        gateway: gateway,
        authRepository: _Session(),
      );
      addTearDown(vm.dispose);

      await tester.pumpWidget(_app(ChangePasswordSheet(viewModel: vm)));
      await tester.pumpAndSettle();

      expect(find.text(en['passwordRuleDigit'] as String), findsOneWidget);
      expect(
        find.text(en['passwordMeetsRequirements'] as String),
        findsNothing,
      );

      await tester.enterText(find.byType(TextField).first, _validPassword);
      await tester.pumpAndSettle();

      expect(
        find.text(en['passwordMeetsRequirements'] as String),
        findsOneWidget,
      );
      expect(find.text(en['passwordRuleDigit'] as String), findsNothing);
    });

    testWidgets(
        'an invalid password never reaches the backend and the error '
        'is localized', (tester) async {
      final gateway = _Gateway();
      addTearDown(gateway.close);
      final vm = ChangePasswordViewModel(
        gateway: gateway,
        authRepository: _Session(),
      );
      addTearDown(vm.dispose);

      await tester.pumpWidget(_app(ChangePasswordSheet(viewModel: vm)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, _validPassword);
      await tester.enterText(find.byType(TextField).last, 'Passw0rde');
      await tester.tap(find.text(en['updatePassword'] as String));
      await tester.pumpAndSettle();

      expect(gateway.changeCalls, 0);
      expect(
        find.text(en['passwordsDoNotMatch'] as String),
        findsOneWidget,
      );
    });

    testWidgets('Arabic renders the sheet with translated strings',
        (tester) async {
      final gateway = _Gateway();
      addTearDown(gateway.close);
      final vm = ChangePasswordViewModel(
        gateway: gateway,
        authRepository: _Session(),
      );
      addTearDown(vm.dispose);

      await tester.pumpWidget(
        _app(
          ChangePasswordSheet(viewModel: vm),
          locale: const Locale('ar'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(ar['changePassword'] as String), findsOneWidget);
      expect(find.text(en['changePassword'] as String), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('Forgot password sheet', () {
    testWidgets('an invalid address is refused without a network call',
        (tester) async {
      final gateway = _Gateway();
      addTearDown(gateway.close);
      final vm = PasswordResetRequestViewModel(gateway: gateway);
      addTearDown(vm.dispose);

      await tester.pumpWidget(_app(PasswordResetRequestSheet(viewModel: vm)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'nope');
      await tester.tap(find.text(en['sendResetLink'] as String));
      await tester.pumpAndSettle();

      expect(gateway.resetCalls, 0);
      expect(
        find.text(en['passwordResetInvalidEmail'] as String),
        findsOneWidget,
      );
    });

    testWidgets('success shows the anti-enumeration message', (tester) async {
      final gateway = _Gateway();
      addTearDown(gateway.close);
      final vm = PasswordResetRequestViewModel(gateway: gateway);
      addTearDown(vm.dispose);

      await tester.pumpWidget(_app(PasswordResetRequestSheet(viewModel: vm)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'person@example.test');
      await tester.tap(find.text(en['sendResetLink'] as String));
      await tester.pumpAndSettle();

      expect(gateway.resetCalls, 1);
      final message = en['passwordResetGenericSuccess'] as String;
      expect(find.text(message), findsOneWidget);
      // The confirmation must not assert that the account exists.
      expect(message.toLowerCase(), contains('if an account exists'));
    });
  });

  group('Reset password screen', () {
    Widget screen(PasswordRecoveryViewModel vm, {Locale? locale}) => _app(
          ChangeNotifierProvider<PasswordRecoveryViewModel>.value(
            value: vm,
            child: const ResetPasswordView(),
          ),
          locale: locale ?? const Locale('en'),
        );

    PasswordRecoveryViewModel recoveryVm(
      _Gateway gateway,
      StreamController<AuthCallbackEvent> callbacks,
    ) {
      final vm = PasswordRecoveryViewModel(
        gateway: gateway,
        authRepository: _Session(),
        callbacks: callbacks.stream,
      );
      addTearDown(vm.dispose);
      return vm;
    }

    testWidgets('an active recovery offers the new-password form',
        (tester) async {
      final gateway = _Gateway();
      addTearDown(gateway.close);
      final callbacks = StreamController<AuthCallbackEvent>.broadcast();
      addTearDown(callbacks.close);
      final vm = recoveryVm(gateway, callbacks);

      await tester.pumpWidget(screen(vm));
      await tester.pumpAndSettle();

      // Without a recovery the screen offers nothing at all.
      expect(find.byType(TextField), findsNothing);
      expect(find.text(en['resetPasswordHeadline'] as String), findsNothing);

      gateway.emit();
      await tester.pumpAndSettle();

      expect(find.text(en['resetPasswordHeadline'] as String), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.text(en['updatePassword'] as String), findsOneWidget);
    });

    testWidgets('a valid reset shows the confirmation, not the form',
        (tester) async {
      final gateway = _Gateway();
      addTearDown(gateway.close);
      final callbacks = StreamController<AuthCallbackEvent>.broadcast();
      addTearDown(callbacks.close);
      final vm = recoveryVm(gateway, callbacks);

      await tester.pumpWidget(screen(vm));
      gateway.emit();
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, _validPassword);
      await tester.enterText(find.byType(TextField).last, _validPassword);
      await tester.tap(find.text(en['updatePassword'] as String));
      await tester.pumpAndSettle();

      expect(gateway.changeCalls, 1);
      expect(
        find.text(en['resetPasswordSuccessTitle'] as String),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('an expired link explains itself and offers a way forward',
        (tester) async {
      final gateway = _Gateway();
      addTearDown(gateway.close);
      final callbacks = StreamController<AuthCallbackEvent>.broadcast();
      addTearDown(callbacks.close);
      final vm = recoveryVm(gateway, callbacks);

      await tester.pumpWidget(screen(vm));
      callbacks.add(
        describeAuthCallback(
          Uri.parse(
            'brokerwallet://auth/reset-password?error=access_denied'
            '&error_code=otp_expired'
            '&error_description=Email+link+is+invalid+or+has+expired',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(en['resetLinkExpiredTitle'] as String),
        findsOneWidget,
      );
      expect(
        find.text(en['requestNewResetLink'] as String),
        findsOneWidget,
      );
      expect(find.text(en['backToLogin'] as String), findsOneWidget);
      // No provider prose, no blank screen.
      expect(find.textContaining('invalid or has expired'), findsNothing);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('Arabic and RTL render the reset screen without overflow',
        (tester) async {
      final gateway = _Gateway();
      addTearDown(gateway.close);
      final callbacks = StreamController<AuthCallbackEvent>.broadcast();
      addTearDown(callbacks.close);
      final vm = recoveryVm(gateway, callbacks);

      await tester.pumpWidget(screen(vm, locale: const Locale('ar')));
      gateway.emit();
      await tester.pumpAndSettle();

      expect(
        find.text(ar['resetPasswordHeadline'] as String),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      // The password value itself stays left-to-right so a typo is visible.
      final field = tester.widget<Directionality>(
        find
            .ancestor(
              of: find.byType(TextField).first,
              matching: find.byType(Directionality),
            )
            .first,
      );
      expect(field.textDirection, TextDirection.ltr);
    });
  });
}
