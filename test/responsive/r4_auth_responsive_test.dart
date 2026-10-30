import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/data/models/phone_otp_args.dart';
import 'package:broker_wallet/src/viewmodels/password_recovery_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/password_reset_request_viewmodel.dart';
import 'package:broker_wallet/src/views/Screens/Sign-Up-Log-In/phone_otp_view.dart';
import 'package:broker_wallet/src/views/Screens/Sign-Up-Log-In/reset_password_view.dart';
import 'package:broker_wallet/src/Views/Screens/Sign-Up-Log-In/splash_screen.dart';
import 'package:broker_wallet/src/views/Widgets/password_reset_request_sheet.dart';
import 'package:broker_wallet/src/views/Widgets/password_form_field.dart';
import 'package:broker_wallet/src/viewmodels/locale_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/login_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/signup_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/phone_otp_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:broker_wallet/src/views/Screens/Sign-Up-Log-In/auth_wrapper.dart';
import 'package:broker_wallet/src/views/Screens/Sign-Up-Log-In/email_verification_view.dart';
import 'package:broker_wallet/src/views/Screens/Sign-Up-Log-In/login_view.dart';
import 'package:broker_wallet/src/views/Screens/Sign-Up-Log-In/signup_view.dart';
import 'package:broker_wallet/src/views/Screens/Sign-Up-Log-In/welcome_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'r2_test_fakes.dart';
import 'responsive_harness.dart';

Widget _withQuietAuth(Widget child) => ChangeNotifierProvider<AuthViewModel>(
      create: (_) => AuthViewModel(
        authRepository: QuietAuthRepository(),
        userRepository: QuietUserRepository(),
        autoInitialize: false,
      ),
      child: child,
    );

class _LocalPasswordGateway implements PasswordCapability {
  @override
  Stream<PasswordRecoverySession> get passwordRecoverySessions =>
      const Stream<PasswordRecoverySession>.empty();

  @override
  bool get isPasswordRecoveryActive => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _expectActionReachable(
  WidgetTester tester,
  Finder action,
  ResponsiveCase scenario,
) async {
  expect(action, findsWidgets);
  await tester.ensureVisible(action.first);
  await tester.pump();
  final rect = tester.getRect(action.first);
  expect(rect.width, greaterThan(0), reason: scenario.toString());
  expect(rect.height, greaterThan(0), reason: scenario.toString());
  expect(rect.top, greaterThanOrEqualTo(0), reason: scenario.toString());
  expect(rect.bottom,
      lessThanOrEqualTo(scenario.size.height - scenario.keyboard + 1),
      reason: scenario.toString());
  expectNoLayoutException(tester, scenario);
}

const _cases = <ResponsiveCase>[
  ResponsiveCase(Size(280, 600), textScale: 2),
  ResponsiveCase(Size(320, 568),
      locale: Locale('ar'), dark: true, textScale: 1.6),
  ResponsiveCase(Size(360, 640),
      keyboard: 280, safeArea: EdgeInsets.only(top: 24, bottom: 20)),
  ResponsiveCase(Size(393, 852), locale: Locale('ar'), textScale: 1.3),
  ResponsiveCase(Size(430, 932), dark: true),
  ResponsiveCase(Size(640, 360),
      locale: Locale('ar'), dark: true, textScale: 2, keyboard: 240),
  ResponsiveCase(Size(600, 800), textScale: 1.6),
  ResponsiveCase(Size(800, 1280),
      locale: Locale('ar'), dark: true, textScale: 1.3),
];

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await prepareResponsiveAssets();
  });

  for (final scenario in _cases) {
    testWidgets('Splash $scenario', (tester) async {
      await pumpResponsive(
        tester,
        scenario,
        home: const SplashScreen(),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(const Duration(milliseconds: 2000));
      expectNoLayoutException(tester, scenario);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Welcome $scenario', (tester) async {
      await pumpResponsive(
        tester,
        scenario,
        home: ChangeNotifierProvider(
          create: (_) => LocaleViewModel(),
          child: const WelcomeView(),
        ),
      );
      expect(find.byType(WelcomeView), findsOneWidget);
      await _expectActionReachable(
          tester, find.byType(ElevatedButton), scenario);
      await _expectActionReachable(
          tester, find.byType(OutlinedButton), scenario);
      expectNoLayoutException(tester, scenario);
    });

    testWidgets('Sign in $scenario', (tester) async {
      await pumpResponsive(tester, scenario, home: const SignInView());
      expect(find.byType(SignInView), findsOneWidget);
      await _expectActionReachable(
          tester, find.byType(ElevatedButton), scenario);
      expectNoLayoutException(tester, scenario);
    });

    testWidgets('Sign up $scenario', (tester) async {
      await pumpResponsive(
        tester,
        scenario,
        home: _withQuietAuth(const SignUpView()),
      );
      expect(find.byType(SignUpView), findsOneWidget);
      await _expectActionReachable(
          tester, find.byType(ElevatedButton), scenario);
      expectNoLayoutException(tester, scenario);
    });

    testWidgets('Email verification $scenario', (tester) async {
      await pumpResponsive(
        tester,
        scenario,
        home: _withQuietAuth(const EmailVerificationView(
          email: 'very.long.account.address.for.layout@example.test',
        )),
      );
      expect(find.byType(EmailVerificationView), findsOneWidget);
      await _expectActionReachable(
          tester, find.byType(OutlinedButton), scenario);
      expectNoLayoutException(tester, scenario);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Phone OTP presentation $scenario', (tester) async {
      await pumpResponsive(
        tester,
        scenario,
        home: const PhoneOtpView(
            args: PhoneOtpArgs(
          phoneNumber: '+971501234567',
          verificationId: 'layout-only',
          isSignup: false,
        )),
      );
      expect(find.byType(PhoneOtpView), findsOneWidget);
      await _expectActionReachable(
          tester, find.byType(ElevatedButton), scenario);
      expectNoLayoutException(tester, scenario);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Reset password active form $scenario', (tester) async {
      final vm = PasswordRecoveryViewModel(
        gateway: _LocalPasswordGateway(),
        authRepository: null,
        callbacks: const Stream.empty(),
      );
      addTearDown(vm.dispose);
      await pumpResponsive(
        tester,
        scenario,
        home: ChangeNotifierProvider.value(
          value: vm,
          child: const ResetPasswordView(),
        ),
      );
      expect(find.byType(ResetPasswordView), findsOneWidget);
      await _expectActionReachable(tester, find.byType(FilledButton), scenario);
      expectNoLayoutException(tester, scenario);
    });

    testWidgets('Forgot password request sheet $scenario', (tester) async {
      final vm = PasswordResetRequestViewModel(gateway: null);
      addTearDown(vm.dispose);
      await pumpResponsive(
        tester,
        scenario,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: PasswordResetRequestSheet(viewModel: vm),
          ),
        ),
      );
      expect(find.byType(PasswordResetRequestSheet), findsOneWidget);
      await _expectActionReachable(tester, find.byType(FilledButton), scenario);
      expectNoLayoutException(tester, scenario);
    });
  }

  testWidgets('Sign in retains typed value and focus across keyboard resize',
      (tester) async {
    const portrait = ResponsiveCase(Size(393, 852), keyboard: 280);
    const landscape = ResponsiveCase(Size(640, 360), keyboard: 240);
    const screen = SignInView();
    await pumpResponsive(tester, portrait, home: screen);
    final email = find.byType(TextField).first;
    await tester.enterText(email, 'invalid-layout-email');
    await tester.pump();
    expect(tester.widget<TextField>(email).focusNode!.hasFocus, isTrue);

    await pumpResponsive(tester, landscape, home: screen);
    expect(tester.widget<TextField>(email).controller!.text,
        'invalid-layout-email');
    expect(tester.widget<TextField>(email).focusNode!.hasFocus, isTrue);
    await _expectActionReachable(tester, email, landscape);
    await _expectActionReachable(
        tester, find.byType(ElevatedButton), landscape);
    expectNoLayoutException(tester, landscape);
  });

  testWidgets('Sign in validation and password visibility on narrow Arabic',
      (tester) async {
    const scenario = ResponsiveCase(Size(280, 600),
        locale: Locale('ar'), textScale: 2, keyboard: 240);
    await pumpResponsive(tester, scenario, home: const SignInView());
    final fields = find.byType(TextField);
    expect(tester.widget<TextField>(fields.at(1)).obscureText, isTrue);
    final toggle = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.icon is SvgPicture,
    );
    await tester.ensureVisible(toggle);
    await tester.pump();
    await tester.tap(toggle);
    await tester.pump();
    expect(tester.widget<TextField>(fields.at(1)).obscureText, isFalse);
    await _expectActionReachable(tester, find.byType(ElevatedButton), scenario);
    await tester.tap(find.byType(ElevatedButton).first);
    await tester.pump();
    final vm = Provider.of<SignInViewModel>(
        tester.element(find.byType(TextField).first),
        listen: false);
    expect(vm.emailError, isNotNull);
    expect(vm.passwordError, isNotNull);
    expectNoLayoutException(tester, scenario);
  });

  testWidgets('Forgot password invalid request shows reachable error',
      (tester) async {
    const scenario = ResponsiveCase(Size(320, 568),
        locale: Locale('ar'), dark: true, textScale: 1.6, keyboard: 280);
    final vm = PasswordResetRequestViewModel(gateway: null);
    addTearDown(vm.dispose);
    await pumpResponsive(
      tester,
      scenario,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: PasswordResetRequestSheet(viewModel: vm),
        ),
      ),
    );
    await _expectActionReachable(tester, find.byType(FilledButton), scenario);
    await tester.tap(find.byType(FilledButton).first);
    await tester.pump();
    expect(vm.errorKey, isNotNull);
    await _expectActionReachable(tester, find.byType(FilledButton), scenario);
  });

  testWidgets('Startup auth wrapper renders its splash without a live session',
      (tester) async {
    const scenario = ResponsiveCase(Size(320, 568),
        locale: Locale('ar'), dark: true, textScale: 1.6);
    await pumpResponsive(tester, scenario,
        home: _withQuietAuth(const AuthWrapper()), settle: false);
    expect(find.byType(SplashScreen), findsOneWidget);
    expectNoLayoutException(tester, scenario);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 2000));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Phone tabs keep their submit actions reachable', (tester) async {
    const scenario = ResponsiveCase(Size(280, 600),
        locale: Locale('ar'), textScale: 2, keyboard: 240);
    await pumpResponsive(tester, scenario, home: const SignInView());
    final signInVm = Provider.of<SignInViewModel>(
        tester.element(find.byType(TextField).first),
        listen: false);
    signInVm.setLoginMethod(LoginMethod.phone);
    await tester.pump();
    await _expectActionReachable(tester, find.byType(ElevatedButton), scenario);

    await pumpResponsive(tester, scenario,
        home: _withQuietAuth(const SignUpView()));
    final signUpVm = Provider.of<SignUpViewModel>(
        tester.element(find.byType(TextField).first),
        listen: false);
    signUpVm.setSignupMethod(SignupMethod.phone);
    await tester.pump();
    await _expectActionReachable(tester, find.byType(ElevatedButton), scenario);
  });

  testWidgets('Sign up validation remains readable with keyboard open',
      (tester) async {
    const scenario = ResponsiveCase(Size(320, 568),
        locale: Locale('ar'), dark: true, textScale: 1.6, keyboard: 280);
    await pumpResponsive(tester, scenario,
        home: _withQuietAuth(const SignUpView()));
    final vm = Provider.of<SignUpViewModel>(
        tester.element(find.byType(TextField).first),
        listen: false);
    final action = find.byType(ElevatedButton);
    await _expectActionReachable(tester, action, scenario);
    await tester.tap(action.first);
    await tester.pump();
    expect(vm.nameError, isNotNull);
    expect(vm.emailError, isNotNull);
    expect(vm.passwordError, isNotNull);
    await _expectActionReachable(tester, action, scenario);
  });

  testWidgets('OTP local validation exposes error without sending a code',
      (tester) async {
    const scenario = ResponsiveCase(Size(320, 568),
        locale: Locale('ar'), dark: true, textScale: 1.6, keyboard: 240);
    await pumpResponsive(tester, scenario,
        home: const PhoneOtpView(
            args: PhoneOtpArgs(
          phoneNumber: '+971501234567',
          verificationId: 'layout-only',
          isSignup: false,
        )));
    final action = find.byType(ElevatedButton);
    await _expectActionReachable(tester, action, scenario);
    final vm = Provider.of<PhoneOtpViewModel>(tester.element(action.first),
        listen: false);
    await tester.tap(action.first);
    await tester.pump();
    expect(vm.errorMessage, isNotNull);
    expectNoLayoutException(tester, scenario);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Reset password local validation keeps update action reachable',
      (tester) async {
    const scenario = ResponsiveCase(Size(280, 600),
        locale: Locale('ar'), textScale: 2, keyboard: 240);
    final vm = PasswordRecoveryViewModel(
      gateway: _LocalPasswordGateway(),
      authRepository: null,
      callbacks: const Stream.empty(),
    );
    addTearDown(vm.dispose);
    await pumpResponsive(tester, scenario,
        home: ChangeNotifierProvider.value(
            value: vm, child: const ResetPasswordView()));
    final firstPassword = find.byType(PasswordFormField).first;
    final toggle = find.descendant(
        of: firstPassword, matching: find.byIcon(Icons.visibility_outlined));
    await tester.ensureVisible(toggle);
    await tester.pump();
    await tester.tap(toggle);
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField).first).obscureText,
        isFalse);
    final action = find.byType(FilledButton);
    await _expectActionReachable(tester, action, scenario);
    await tester.tap(action.first);
    await tester.pump();
    expect(vm.errorKey, isNotNull);
    await _expectActionReachable(tester, action, scenario);
  });
}
