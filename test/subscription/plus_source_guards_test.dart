import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-level guards for the Plus subscription UI checkpoint.
///
/// These read the checked-in source; they do not prove runtime behaviour. They
/// exist so the rules of this checkpoint — no direct payment UI, no fake
/// entitlement writes, no hard-coded prices, no billing SDK — cannot regress
/// unnoticed.

const _plusUiDirectories = [
  'lib/src/views/Widgets/plus',
  'lib/src/views/Screens/home/Profile/SubscriptionPlan',
];

const _plusUiFiles = [
  'lib/src/viewmodels/plus_subscription_viewmodel.dart',
  'lib/src/common/routes/plus_routes.dart',
  'lib/src/common/localization/plus_localization.dart',
];

const _plusDataDirectories = [
  'lib/src/data/models/subscription',
  'lib/src/services/subscription',
];

List<File> _dartFiles(Iterable<String> directories,
    [Iterable<String> files = const []]) {
  final result = <File>[];
  for (final dir in directories) {
    for (final entity in Directory(dir).listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) result.add(entity);
    }
  }
  for (final path in files) {
    result.add(File(path));
  }
  return result;
}

/// Source with comments removed, so a rule can mention what it forbids.
String _code(File file) {
  return file
      .readAsStringSync()
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');
}

String _name(File file) => file.path.replaceAll('\\', '/');

void main() {
  final uiFiles = _dartFiles(_plusUiDirectories, _plusUiFiles);
  final allPlusFiles = [..._dartFiles(_plusDataDirectories), ...uiFiles];

  group('no direct payment UI', () {
    test('the old payment-method flow no longer exists', () {
      for (final path in const [
        'lib/src/views/Screens/home/Profile/payment_selection_view.dart',
        'lib/src/viewmodels/payment_viewmodel.dart',
        'lib/src/views/Screens/home/Profile/SubscriptionPlan/subscription_view.dart',
        'lib/src/views/Screens/home/Profile/SubscriptionPlan/subscription_viewmodel.dart',
      ]) {
        expect(File(path).existsSync(), isFalse, reason: path);
      }
    });

    test('nothing in the Plus code collects or names a payment method', () {
      final forbidden = RegExp(
        r'cardNumber|cvv|cvc|expiryDate|creditCard|PayPal|Stripe|Telr|'
        r'ApplePay|GooglePay|PaymentMethod\.|\bvisa\b|mastercard|'
        r'credit_card|Icons\.payment\b|savedCard|defaultCard|addCard|'
        r'cardHolder',
        caseSensitive: false,
      );
      for (final file in allPlusFiles) {
        expect(forbidden.hasMatch(_code(file)), isFalse, reason: _name(file));
      }
    });

    test('no Plus screen has a text field, a form or a payment input', () {
      final input = RegExp(
        r'TextField|TextFormField|\bForm\(|InputDecoration|'
        r'TextInputType\.number|CreditCard',
      );
      for (final file in uiFiles) {
        expect(input.hasMatch(_code(file)), isFalse, reason: _name(file));
      }
    });

    test('only the manage sheet ever opens an external store page', () {
      for (final file in allPlusFiles) {
        final opens = _code(file).contains('launchUrl(');
        expect(opens, _name(file).endsWith('plus_manage_sheet.dart'),
            reason: _name(file));
      }
    });

    test('no billing or payment SDK is in pubspec.yaml', () {
      final dependencies = File('pubspec.yaml')
          .readAsLinesSync()
          .where((line) => !line.trimLeft().startsWith('#'))
          .join('\n');
      for (final package in const [
        'purchases_flutter',
        'purchases_ui_flutter',
        'in_app_purchase',
        'flutter_stripe',
        'stripe',
        'pay:',
        'flutter_paypal',
      ]) {
        expect(dependencies.contains(package), isFalse, reason: package);
      }
    });
  });

  group('no fake entitlement', () {
    test('no Plus code writes subscription data to any backend', () {
      final storage = RegExp(
        r'cloud_firestore|FirebaseFirestore|supabase|Supabase|'
        r"\.collection\(|\.from\(|FieldValue|SharedPreferences",
      );
      for (final file in allPlusFiles) {
        // The usage section's read of the legacy counters is the one
        // documented exception; it reads, it never writes.
        if (_name(file).endsWith('my_plan_usage_section.dart')) continue;
        expect(storage.hasMatch(_code(file)), isFalse, reason: _name(file));
      }
    });

    test('the legacy usage read never touches the old plan fields', () {
      final code = _code(File(
          'lib/src/views/Screens/home/Profile/SubscriptionPlan/my_plan_usage_section.dart'));
      expect(code.contains("['plan']"), isFalse);
      expect(code.contains("['subscription']"), isFalse);
      expect(code.contains('.set('), isFalse);
      expect(code.contains('.update('), isFalse);
    });

    test('the test-only subscribe buttons are gone from the UI', () {
      final text = [
        for (final file in uiFiles) _code(file),
      ].join('\n');
      expect(text.contains('Test Subscribe'), isFalse);
      expect(text.contains('testSubscribe'), isFalse);
      expect(text.contains('testUnsubscribe'), isFalse);
    });

    test('the view model has no isPremium-style flag', () {
      final code =
          _code(File('lib/src/viewmodels/plus_subscription_viewmodel.dart'));
      expect(
          RegExp(r'\bisPremium\b|\bisPlus\b|\bisSubscribed\b').hasMatch(code),
          isFalse);
    });
  });

  group('debug preview stays debug-only', () {
    test('the preview gateway is only constructed behind kDebugMode', () {
      final constructions = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (_name(entity).endsWith('debug_plus_billing_gateway.dart')) continue;
        final code = _code(entity);
        if (code.contains('DebugPlusBillingGateway(')) {
          constructions.add(_name(entity));
          // Every construction must sit in a `kDebugMode ?` expression.
          final guardedCount = RegExp(
            r'kDebugMode\s*\?\s*DebugPlusBillingGateway\(',
          ).allMatches(code).length;
          final totalCount =
              RegExp(r'DebugPlusBillingGateway\(').allMatches(code).length;
          expect(guardedCount, totalCount,
              reason:
                  '${_name(entity)} constructs the preview gateway unguarded');
        }
      }
      expect(constructions, ['lib/main.dart']);
    });

    test('every debug entry point checks kDebugMode', () {
      final sheet = _code(
          File('lib/src/views/Widgets/plus/plus_debug_preview_sheet.dart'));
      expect(
          'if (!kDebugMode)'.allMatches(sheet).length, greaterThanOrEqualTo(3));

      final viewModel =
          _code(File('lib/src/viewmodels/plus_subscription_viewmodel.dart'));
      for (final method in const [
        'debugApplyEntitlement',
        'debugShowPurchasePhase',
        'debugShowRestorePhase',
        'debugReloadOffering',
        'debugSetStore',
        'debugReset',
      ]) {
        final start = viewModel.indexOf('$method(');
        expect(start, greaterThan(-1), reason: method);
        final body = viewModel.substring(start, start + 160);
        expect(body.contains('if (!kDebugMode) return;'), isTrue,
            reason: method);
      }
    });

    test('the preview data is the only place with sample prices', () {
      final priced = RegExp(r"'(AED|USD|EUR|SAR)\s?\d");
      for (final file in allPlusFiles) {
        if (_name(file).endsWith('debug_plus_billing_gateway.dart')) continue;
        expect(priced.hasMatch(_code(file)), isFalse, reason: _name(file));
      }
    });
  });

  group('design system', () {
    test('Plus UI uses theme colours, not raw or purple/amber ones', () {
      final forbidden = RegExp(
        r'Colors\.(purple|deepPurple|amber|orange|green|red|blue)\b|'
        r'Color\(0x|Color\.fromARGB|Color\.fromRGBO',
      );
      for (final file in uiFiles) {
        expect(forbidden.hasMatch(_code(file)), isFalse, reason: _name(file));
      }
    });

    test('Plus UI has no hard-coded currency or fixed discount', () {
      for (final file in uiFiles) {
        final code = _code(file);
        expect(code.contains('AED'), isFalse, reason: _name(file));
        expect(RegExp(r"'Save \d").hasMatch(code), isFalse,
            reason: _name(file));
      }
    });

    test('Plus UI uses direction-aware geometry for text alignment', () {
      for (final file in uiFiles) {
        final code = _code(file);
        expect(code.contains('TextAlign.left'), isFalse, reason: _name(file));
        expect(code.contains('TextAlign.right'), isFalse, reason: _name(file));
        expect(code.contains('Alignment.centerLeft'), isFalse,
            reason: _name(file));
        expect(code.contains('Alignment.centerRight'), isFalse,
            reason: _name(file));
      }
    });
  });

  group('entry points', () {
    test('the existing upgrade entry points open the Plus experience', () {
      for (final path in const [
        'lib/src/views/Screens/home/Profile/profile_view.dart',
        'lib/src/services/quota_helper.dart',
        'lib/src/widgets/quota_aware_section_page.dart',
      ]) {
        final code = _code(File(path));
        expect(code.contains("'/subscription'"), isFalse, reason: path);
        expect(code.contains("'/payment-selection"), isFalse, reason: path);
      }
      expect(
        _code(File('lib/src/services/quota_helper.dart')),
        contains('PlusNavigation.openPaywall'),
      );
      expect(
        _code(File('lib/src/views/Screens/home/Profile/profile_view.dart')),
        contains('PlusNavigation.open('),
      );
    });

    test('Profile has exactly one Subscription & Billing entry', () {
      final code = _code(
        File('lib/src/views/Screens/home/Profile/profile_view.dart'),
      );
      expect(code.contains("'plusBillingTitle'"), isTrue);
      expect('PlusNavigation.open('.allMatches(code).length, 1);
      expect('SvgIcon.premiumPlan'.allMatches(code).length, 1);
      // The former separate "My Plan" row is merged into this one screen.
      expect(code.contains("'myPlan'"), isFalse);
      expect(code.contains('PlusRoutes.myPlan'), isFalse);
      expect(code.contains('PlusRoutes.billing'), isFalse,
          reason: 'Profile goes through PlusNavigation.open');
    });

    test('the Subscription & Billing hub points to the store, not a card', () {
      final code = _code(File(_screen('subscription_billing_view.dart')));
      // It names who owns the payment method and sends each task to a screen.
      expect(code, contains('plusManagedByText'));
      for (final route in const [
        'PlusRoutes.manage',
        'PlusRoutes.paymentMethods',
        'PlusRoutes.history',
        'PlusRoutes.restore',
        'PlusRoutes.usage',
        'PlusRoutes.help',
        'PlusRoutes.legal',
      ]) {
        expect(code, contains(route), reason: route);
      }
    });

    test('the hub carries no details, usage counters or legal text itself', () {
      final code = _code(File(_screen('subscription_billing_view.dart')));
      for (final fragment in const [
        'MyPlanUsageSection',
        'PlusDetailRow',
        'PlusLegalFooter',
        'PlusStepRow',
        "'plusSubscriptionInfoBody'",
      ]) {
        expect(code.contains(fragment), isFalse, reason: fragment);
      }
    });

    test('the payment-methods screen hands off to the store and nowhere else',
        () {
      final code = _code(File(_screen('plus_payment_methods_view.dart')));
      for (final action in const [
        'PlusManageAction.managePaymentMethods',
        'PlusManageAction.addPaymentMethod',
        'PlusManageAction.backupPaymentMethods',
        'PlusManageAction.updatePaymentMethod',
        'PlusManageAction.manage',
      ]) {
        expect(code, contains(action), reason: action);
      }
      expect(code.contains('launchUrl('), isFalse);
    });

    test('hand-off sheets explain and never touch the subscription', () {
      for (final path in const [
        'lib/src/views/Widgets/plus/plus_manage_sheet.dart',
        'lib/src/views/Widgets/plus/plus_secure_checkout_sheet.dart',
      ]) {
        final code = _code(File(path));
        for (final fragment in const [
          'PlusSubscriptionViewModel',
          'applyEntitlement',
          'beginPurchase',
          'restorePurchases',
          'context.read',
          'context.watch',
        ]) {
          expect(code.contains(fragment), isFalse, reason: '$path: $fragment');
        }
      }
    });

    test('the purchase review goes through the secure checkout step', () {
      final code = _code(File(_screen('plus_purchase_review_view.dart')));
      expect(code, contains('PlusSecureCheckoutSheet.show'));
      // The purchase only begins after that step resolves.
      expect(
        code.indexOf('PlusSecureCheckoutSheet.show'),
        lessThan(code.indexOf('beginPurchase')),
      );
    });

    test('the router registers the Plus routes and redirects the old ones', () {
      final app = _code(File('lib/app.dart'));
      for (final route in const [
        'PlusRoutes.paywall',
        'PlusRoutes.review',
        'PlusRoutes.purchase',
        'PlusRoutes.restore',
        'PlusRoutes.billing',
        'PlusRoutes.manage',
        'PlusRoutes.changePeriod',
        'PlusRoutes.paymentMethods',
        'PlusRoutes.history',
        'PlusRoutes.help',
        'PlusRoutes.legal',
        'PlusRoutes.usage',
        'PlusRoutes.myPlan',
        'PlusRoutes.legacySubscription',
        'PlusRoutes.legacyPaymentSelection',
      ]) {
        expect(app.contains(route), isTrue, reason: route);
      }
      expect(app.contains('PaymentSelectionView'), isFalse);
      expect(app.contains('SubscriptionView('), isFalse);
    });

    test('every Subscription & Billing route is declared once', () {
      final routes = _code(File('lib/src/common/routes/plus_routes.dart'));
      final paths = RegExp(r"static const String \w+ = '(/[^']+)';")
          .allMatches(routes)
          .map((m) => m.group(1)!)
          .toList();
      expect(paths.toSet().length, paths.length,
          reason: 'a route path is declared twice');
      // Seven tasks live under the hub: manage, change period, payment
      // methods, history, help, legal and usage.
      expect(
        paths.where((p) => p.startsWith('/subscription-billing/')).length,
        7,
      );
    });
  });
}

String _screen(String file) =>
    'lib/src/views/Screens/home/Profile/SubscriptionPlan/$file';
