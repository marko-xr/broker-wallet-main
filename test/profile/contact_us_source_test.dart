import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final screen = File(
    'lib/src/views/Screens/home/Profile/contact_us_view.dart',
  ).readAsStringSync();
  final profile = File(
    'lib/src/views/Screens/home/Profile/profile_view.dart',
  ).readAsStringSync();
  final help = File(
    'lib/src/views/Screens/home/Profile/help_support_view.dart',
  ).readAsStringSync();
  final routes = File('lib/app.dart').readAsStringSync();

  test('Contact Us has a real destination from both entry points', () {
    expect(routes, contains("path: '/contact-us'"));
    expect(routes, contains('const ContactUsView()'));
    expect(profile, contains("onTap: () => context.push('/contact-us')"));
    expect(help, contains("onTap: () => context.push('/contact-us')"));
    expect(profile, isNot(contains('contactUsPlaceholder')));
    expect(help, isNot(contains('contactUsPlaceholder')));
    expect(screen, isNot(contains('InfoPlaceholderView')));
  });

  test('mail action sends only the official recipient and subject', () {
    expect(screen, contains("supportEmail = 'brokerwallet@nmodigital.com'"));
    expect(screen, contains("supportSubject = 'Broker Wallet Support'"));
    expect(screen, contains('mailto:\$supportEmail?subject='));
    expect(screen, contains('Uri.encodeComponent(supportSubject)'));
    expect(screen, contains('LaunchMode.externalApplication'));
    expect(screen, contains('ClipboardData(text: supportEmail)'));
    expect(
      screen,
      contains("fromFallback ? 'contactFallbackCopied' : 'contactEmailCopied'"),
    );
    expect(screen, isNot(contains('currentUser')));
    expect(screen, isNot(contains('authId')));
    expect(screen, isNot(contains('token')));
    expect(screen, isNot(contains('diagnostic')));
  });

  test('support page uses a scrollable top-down card layout', () {
    expect(screen, contains('child: SingleChildScrollView('));
    expect(screen, contains('EdgeInsets.fromLTRB(20, 16, 20, 32)'));
    expect(screen, contains("loc.translate('contactHowCanWeHelp')"));
    expect(screen, contains("loc.translate('contactSupportDescription')"));
    expect(screen, contains('Card('));
    expect(
      screen,
      matches(RegExp(
        r'SelectableText\(\s*supportEmail,\s*textDirection: TextDirection\.ltr',
      )),
    );
    expect(screen, contains('textDirection: TextDirection.ltr'));
    expect(screen, contains('TextButton.icon('));
    expect(screen, contains('onPressed: () => _copyEmail(context)'));
    expect(screen, contains("loc.translate('contactSecurityNote')"));
  });

  test('English and Arabic contact copy is present and current', () {
    final en = jsonDecode(File(
      'lib/src/common/localization/app_en.arb',
    ).readAsStringSync()) as Map<String, dynamic>;
    final ar = jsonDecode(File(
      'lib/src/common/localization/app_ar.arb',
    ).readAsStringSync()) as Map<String, dynamic>;
    const keys = [
      'contactUs',
      'contactBrandName',
      'contactBrandByline',
      'contactHowCanWeHelp',
      'contactSupportDescription',
      'contactEmailLabel',
      'emailSupport',
      'contactCopyEmail',
      'contactEmailCopied',
      'contactFallbackCopied',
      'contactEmailUnavailable',
      'contactSecurityNote',
      'contactUsHint',
    ];
    for (final translations in [en, ar]) {
      for (final key in keys) {
        expect(translations[key], isA<String>().having(
          (value) => value.isNotEmpty,
          'nonempty text',
          isTrue,
        ));
      }
      expect(translations, isNot(contains('contactUsPlaceholder')));
    }
    expect(en['contactBrandName'], 'Broker Wallet');
    expect(en['contactBrandByline'], 'by NMO Digital');
    expect(en['contactHowCanWeHelp'], 'How can we help?');
    expect(
      en['contactSupportDescription'],
      'Our support team can help with questions, technical issues, and account assistance.',
    );
    expect(en['contactEmailLabel'], 'Support Email');
    expect(en['emailSupport'], 'Email Support');
    expect(en['contactCopyEmail'], 'Copy Email');
    expect(ar['contactUs'], 'تواصل معنا');
    expect(ar['contactBrandName'], 'محفظة الوسيط');
    expect(ar['contactBrandByline'], 'من NMO Digital');
    expect(ar['contactHowCanWeHelp'], 'كيف يمكننا مساعدتك؟');
    expect(
      ar['contactSupportDescription'],
      'فريق دعم محفظة الوسيط جاهز لمساعدتك في الأسئلة والمشكلات التقنية ومشكلات الحساب.',
    );
    expect(ar['contactEmailLabel'], 'البريد الإلكتروني للدعم');
    expect(ar['emailSupport'], 'مراسلة الدعم');
    expect(ar['contactCopyEmail'], 'نسخ البريد الإلكتروني');
    expect(en['contactEmailCopied'], 'Support email copied');
    expect(ar['contactEmailCopied'], 'تم نسخ بريد الدعم');
    expect(
      en['contactSecurityNote'],
      'For your security, our support team will never ask for your password or verification code.',
    );
    expect(
      ar['contactSecurityNote'],
      'لحمايتك، لن يطلب منك فريق الدعم كلمة المرور أو رمز التحقق.',
    );
  });
}
