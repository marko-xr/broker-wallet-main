import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/themes/app_theme.dart';
import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/help_support_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/legal_information_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/security_view.dart';
import 'package:broker_wallet/src/views/Widgets/settings_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

late Map<String, dynamic> _en;
late Map<String, dynamic> _ar;

Widget _app(Widget child, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    locale: locale,
    theme: AppTheme.lightTheme,
    darkTheme: AppTheme.darkTheme,
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
    home: child,
  );
}

UserModel _user({String email = 'broker@example.test', String? phone}) {
  return UserModel(
    uid: 'profile-completion-test-user',
    name: 'Broker',
    email: email,
    phoneNumber: phone,
    createdAt: DateTime(2026, 9, 14),
    subscription: UserSubscription(
      plan: 'free',
      isActive: false,
      features: const [],
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await AppLocalizations.preloadAllLanguages();
    _en = json.decode(
      File('lib/src/common/localization/app_en.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
    _ar = json.decode(
      File('lib/src/common/localization/app_ar.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
  });

  test('Profile Completion 1 localization keys exist in English and Arabic',
      () {
    const keys = [
      'profileIdentityUnavailable',
      'signingOut',
      'logoutFailed',
      'helpAccountSecurity',
      'helpFeedback',
      'helpLegalInformation',
      'helpEditProfileHint',
      'sendFeedback',
      'sendFeedbackHint',
      'contactUsHint',
      'securityCenter',
      'signInIdentity',
      'accountProtection',
      'noEmailAdded',
      'notAdded',
      'securityPasswordHint',
      'legalInformationStatus',
      'legalContentPending',
      'legalContentAvailableBeforeRelease',
    ];

    for (final key in keys) {
      expect(_en[key], isA<String>(), reason: 'English $key is missing');
      expect(_ar[key], isA<String>(), reason: 'Arabic $key is missing');
    }
  });

  testWidgets('SettingsTile mirrors its chevron for RTL', (tester) async {
    await tester.pumpWidget(
      _app(
        const Scaffold(
          body: SettingsTile(
            iconAsset: 'unused',
            materialIcon: Icons.shield_outlined,
            title: 'Security',
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(find.byIcon(Icons.chevron_left), findsNothing);

    await tester.pumpWidget(
      _app(
        const Scaffold(
          body: SettingsTile(
            iconAsset: 'unused',
            materialIcon: Icons.shield_outlined,
            title: 'الأمان',
          ),
        ),
        locale: const Locale('ar'),
      ),
    );
    await tester.pump();
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(find.byIcon(Icons.chevron_left), findsNothing);
  });

  testWidgets('Help and legal destinations construct with localized content',
      (tester) async {
    await tester.pumpWidget(_app(const HelpSupportView()));
    await tester.pumpAndSettle();
    expect(find.text(_en['helpAccountSecurity'] as String), findsOneWidget);
    expect(find.text(_en['sendFeedback'] as String), findsOneWidget);

    await tester.pumpWidget(_app(const PrivacyPolicyView()));
    await tester.pumpAndSettle();
    expect(find.text(_en['legalContentPending'] as String), findsOneWidget);
    expect(
      find.text(_en['legalContentAvailableBeforeRelease'] as String),
      findsOneWidget,
    );

    await tester.pumpWidget(_app(const TermsConditionsView()));
    await tester.pumpAndSettle();
    expect(find.text(_en['termsConditions'] as String), findsWidgets);
  });

  testWidgets('Security safely presents real identity values and empty states',
      (tester) async {
    await tester.pumpWidget(
      _app(SecurityView(user: _user(phone: '+971501234567'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('broker@example.test'), findsOneWidget);
    expect(find.text('+971501234567'), findsOneWidget);

    await tester.pumpWidget(_app(SecurityView(user: _user(email: ''))));
    await tester.pumpAndSettle();
    expect(find.text(_en['noEmailAdded'] as String), findsOneWidget);
    expect(find.text(_en['notAdded'] as String), findsOneWidget);
  });

  test('Profile uses the approved destinations and existing account flows', () {
    final profile = File(
      'lib/src/views/Screens/home/Profile/profile_view.dart',
    ).readAsStringSync();
    final security = File(
      'lib/src/views/Screens/home/Profile/security_view.dart',
    ).readAsStringSync();
    final app = File('lib/app.dart').readAsStringSync();

    for (final route in [
      '/help-support',
      '/security',
      '/privacy-policy',
      '/terms-conditions',
    ]) {
      expect(profile, contains("context.push('$route')"));
      expect(app, contains("path: '$route'"));
    }
    expect(profile, isNot(contains('user@example.com')));
    expect(security, contains('context.watch<AuthViewModel>()'));
    expect(security, contains('showDeleteAccountFlow(context)'));
    expect(security, isNot(contains('Supabase')));
  });
}
