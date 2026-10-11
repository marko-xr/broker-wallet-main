import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final profile = File(
    'lib/src/views/Screens/home/Profile/profile_view.dart',
  ).readAsStringSync();
  final help = File(
    'lib/src/views/Screens/home/Profile/help_support_view.dart',
  ).readAsStringSync();
  final security = File(
    'lib/src/views/Screens/home/Profile/security_view.dart',
  ).readAsStringSync();
  final routes = File('lib/app.dart').readAsStringSync();
  final myPlan = File(
    'lib/src/views/Screens/home/Profile/my_plan_view.dart',
  ).readAsStringSync();
  final subscriptions = File(
    'lib/src/views/Screens/home/Profile/SubscriptionPlan/subscription_view.dart',
  ).readAsStringSync();
  final billing = File(
    'lib/src/views/Screens/home/Profile/billing_payments_view.dart',
  ).readAsStringSync();
  final paymentSelection = File(
    'lib/src/views/Screens/home/Profile/payment_selection_view.dart',
  ).readAsStringSync();
  final export = File(
    'lib/src/views/Screens/home/Profile/export_data_view.dart',
  ).readAsStringSync();
  final notificationSettings = File(
    'lib/src/views/Screens/home/Profile/notification_settings_view.dart',
  ).readAsStringSync();
  final en = jsonDecode(File(
    'lib/src/common/localization/app_en.arb',
  ).readAsStringSync()) as Map<String, dynamic>;
  final ar = jsonDecode(File(
    'lib/src/common/localization/app_ar.arb',
  ).readAsStringSync()) as Map<String, dynamic>;

  test('main Profile has exactly the approved sections and rows in order', () {
    final start = profile.indexOf('// ===== Category 1:');
    final end = profile.indexOf('const SizedBox(height: 96)', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final list = profile.substring(start, end);
    const sections = [
      ('generalSettings', ['language', 'theme', 'notifications']),
      ('planBilling', ['myPlan', 'subscriptions', 'billingPayments']),
      ('accountSecurity', ['security', 'logout']),
      ('privacyData', ['exportData', 'privacyPolicy']),
      ('profileSupport', ['contactUs', 'sendFeedback']),
      ('legalAndApp', [
        'termsConditions',
        'aboutBrokerWallet',
        'shareApp',
      ]),
    ];
    final actual = RegExp(
      r"^\s*title:\s*localization\.translate\('([^']+)'\)",
      multiLine: true,
    ).allMatches(list).map((match) => match.group(1)!).toList();
    // Check order section by section, including the section heading.
    final ordered = [
      for (final (header, rows) in sections) ...[header, ...rows],
    ];
    expect(actual, ordered);
    expect(actual.length, 21);
    expect(profile, contains("localization.translate('editProfile')"));
    expect(profile, contains('onPressed: vm.editProfile'));
  });

  test('Delete Account and paywall are absent from main Profile', () {
    for (final key in ['helpSupport', 'deleteAccount']) {
      expect(profile, isNot(contains("localization.translate('$key')")));
    }
    for (final route in ['/help-support', '/payment-selection', '/paywall']) {
      expect(profile, isNot(contains(route)));
    }
    expect(profile, isNot(contains('RevenueCat')));
    expect(help, isNot(contains("loc.translate('notifications')")));
    expect(help, isNot(contains("context.push('/notification-settings')")));
    expect(routes, contains("path: '/help-support'"));
  });

  test('remaining actions retain their destinations', () {
    for (final route in [
      '/language',
      '/notification-settings',
      '/my-plan',
      '/subscription',
      '/billing-payments',
      '/security',
      '/export-data',
      '/contact-us',
      '/feedback',
      '/privacy-policy',
      '/terms-conditions',
      '/about',
    ]) {
      expect(profile, contains("context.push('$route')"));
      expect(routes, contains("path: '$route'"));
    }
    expect(profile, contains('onSwitch: vm.toggleTheme'));
    expect(profile, contains('onTap: vm.isLoggingOut ? null : vm.logout'));
    expect(profile, contains('onTap: vm.shareApp'));
    expect(security, contains('showDeleteAccountFlow(context)'));
    expect(security, contains("loc.translate('deleteAccount')"));
    expect(myPlan, contains("context.push('/subscription')"));
    expect(routes, contains("path: '/payment-selection/:plan'"));
    expect(paymentSelection, contains('const SubscriptionView()'));
    expect(subscriptions, contains("context.push('/privacy-policy')"));
    expect(subscriptions, contains("context.push('/terms-conditions')"));
  });

  test('deferred screens expose no fabricated plan, checkout, or export', () {
    expect(myPlan, contains("loc.translate('planInformationUnavailable')"));
    expect(myPlan, isNot(contains('FirebaseFirestore')));
    expect(subscriptions, contains("loc.translate('storeProductsNotConnected')"));
    expect(subscriptions, contains('onPressed: null'));
    expect(subscriptions, isNot(contains('SubscriptionViewModel')));
    expect(billing, contains("loc.translate('billingStoreExplanation')"));
    expect(billing, isNot(contains('creditCard')));
    expect(paymentSelection, isNot(contains('PaymentViewModel')));
    expect(export, contains("loc.translate('exportNotConnected')"));
    expect(export, contains('onPressed: null'));
    for (final screen in [
      myPlan,
      subscriptions,
      billing,
      paymentSelection,
      export,
    ]) {
      expect(screen, isNot(contains('RevenueCat')));
      expect(screen, isNot(contains('paymentSuccessMessage')));
      expect(RegExp(r'\b\d+\s*AED\b').hasMatch(screen), isFalse);
      expect(RegExp(r'\b(?:prod|price|sku)_[A-Za-z0-9_]+\b')
          .hasMatch(screen), isFalse);
    }
  });

  test('notification preferences and the push limitation stay visible', () {
    expect(notificationSettings, contains('vm.toggleMaster'));
    expect(notificationSettings, contains("vm.toggleSetting('push', value)"));
    expect(notificationSettings,
        contains(".translate('pushDeliveryNotConfigured')"));
  });

  test('English and Arabic section labels match the approved structure', () {
    expect(en['generalSettings'], 'General Settings');
    expect(ar['generalSettings'], 'الإعدادات العامة');
    expect(en['planBilling'], 'Plan & Billing');
    expect(ar['planBilling'], 'الخطة والفوترة');
    expect(en['accountSecurity'], 'Account & Security');
    expect(ar['accountSecurity'], 'الحساب والأمان');
    expect(en['privacyData'], 'Privacy & Data');
    expect(ar['privacyData'], 'البيانات والخصوصية');
    expect(en['profileSupport'], 'Support');
    expect(ar['profileSupport'], 'الدعم');
    expect(en['legalAndApp'], 'Legal & App');
    expect(ar['legalAndApp'], 'المعلومات القانونية والتطبيق');
    for (final key in [
      'language',
      'theme',
      'notifications',
      'myPlan',
      'subscriptions',
      'billingPayments',
      'security',
      'logout',
      'exportData',
      'contactUs',
      'sendFeedback',
      'privacyPolicy',
      'termsConditions',
      'aboutBrokerWallet',
      'shareApp',
    ]) {
      expect(en[key], isA<String>().having((s) => s.isNotEmpty, 'text', true));
      expect(ar[key], isA<String>().having((s) => s.isNotEmpty, 'text', true));
    }
  });
}
