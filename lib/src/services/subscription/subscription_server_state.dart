import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_presentation.dart';
import 'package:flutter/foundation.dart';

/// What the app may conclude before a protected write. The server still
/// decides the write itself; this only avoids sending one it will refuse.
enum QuotaDecision { allowed, limitReached, readOnly, unavailable }

/// The one state the trusted server reported for the signed-in account.
///
/// Parsing is strict: anything missing or unexpected throws [FormatException],
/// so an answer that cannot be understood is "unavailable" and never Free or
/// Plus. Nothing here is persisted.
@immutable
class SubscriptionServerState {
  const SubscriptionServerState({
    required this.status,
    required this.isPlus,
    required this.readOnly,
    required this.isTest,
    required this.created,
    this.cycle,
    this.provider,
    this.startedAt,
    this.paidThrough,
    this.nextChargeAt,
    this.items = const [],
    this.testModeAvailable = false,
    this.testScenario,
    this.testExpiresAt,
  });

  final SubscriptionStatus status;
  final bool isPlus;
  final bool readOnly;

  /// True when the current access comes from a Staging test entitlement.
  final bool isTest;
  final Map<UsageCategory, int> created;
  final PlusBillingCycle? cycle;
  final BillingProvider? provider;
  final DateTime? startedAt;
  final DateTime? paidThrough;
  final DateTime? nextChargeAt;
  final List<ItemEditUsage> items;

  /// The server says this account may use the Staging test control.
  final bool testModeAvailable;
  final String? testScenario;
  final DateTime? testExpiresAt;

  /// The primary test switch: ON only for the server's active `plus` scenario.
  bool get testPlusOn => testModeAvailable && testScenario == 'plus';

  static const Map<String, SubscriptionStatus> _statuses = {
    'free': SubscriptionStatus.free,
    'plus_renewing': SubscriptionStatus.plusRenewing,
    'plus_cancel_scheduled': SubscriptionStatus.plusCancelScheduled,
    'payment_issue': SubscriptionStatus.paymentIssue,
    'expired_over_limit': SubscriptionStatus.expiredOverLimit,
    'expired_within_free': SubscriptionStatus.expiredWithinFree,
  };

  static const Set<SubscriptionStatus> _plusStatuses = {
    SubscriptionStatus.plusRenewing,
    SubscriptionStatus.plusCancelScheduled,
    SubscriptionStatus.paymentIssue,
  };

  static const Map<String, UsageCategory> _categories = {
    'requests': UsageCategory.requests,
    'offers': UsageCategory.offers,
    'owners': UsageCategory.owners,
    'offices': UsageCategory.offices,
    'brokers': UsageCategory.brokers,
    'watchmen': UsageCategory.watchmen,
    'quotations': UsageCategory.quotations,
    'scanner': UsageCategory.scanner,
    'signature': UsageCategory.signature,
    'image_to_pdf': UsageCategory.imagesToPdf,
    'combine_pdfs': UsageCategory.combinePdfs,
  };

  /// The app's older section names for two Toolkit tools.
  static const Map<String, UsageCategory> _appSectionNames = {
    'imageToPdf': UsageCategory.imagesToPdf,
    'combinePdfs': UsageCategory.combinePdfs,
  };

  /// The category of a server or app section name, or null if unknown.
  static UsageCategory? categoryOf(String section) =>
      _categories[section] ?? _appSectionNames[section];

  factory SubscriptionServerState.fromJson(Object? raw) {
    if (raw is! Map) throw const FormatException('state');
    final plan = raw['plan'];
    final status = _statuses[raw['status']];
    final readOnly = raw['read_only'];
    final isTest = raw['is_test'];
    final usage = raw['usage'];
    if ((plan != 'free' && plan != 'plus') ||
        status == null ||
        readOnly is! bool ||
        isTest is! bool ||
        usage is! Map) {
      throw const FormatException('state');
    }
    final isPlus = plan == 'plus';
    // A plan and a status that disagree are not a state to act on.
    if (isPlus != _plusStatuses.contains(status) || (isPlus && readOnly)) {
      throw const FormatException('state');
    }

    final created = <UsageCategory, int>{};
    for (final entry in _categories.entries) {
      final count = usage[entry.key];
      if (count is! int || count < 0) throw const FormatException('usage');
      created[entry.value] = count;
    }

    final items = <ItemEditUsage>[];
    final rawItems = raw['items'];
    if (rawItems is! List) throw const FormatException('items');
    for (final item in rawItems) {
      if (item is! Map) throw const FormatException('items');
      final category = _categories[item['section']];
      final used = item['edits_used'];
      if (category == null || used is! int || used < 0) {
        throw const FormatException('items');
      }
      final title = item['title'];
      items.add(ItemEditUsage(
        category: category,
        title: title is String ? title : '',
        editsUsed: used,
      ));
    }

    final testMode = raw['test_mode'];
    if (testMode is! Map || testMode['available'] is! bool) {
      throw const FormatException('test_mode');
    }
    final scenario = testMode['scenario'];

    return SubscriptionServerState(
      status: status,
      isPlus: isPlus,
      readOnly: readOnly,
      isTest: isTest,
      created: Map.unmodifiable(created),
      cycle: switch (raw['cycle']) {
        'monthly' => PlusBillingCycle.monthly,
        'annual' => PlusBillingCycle.annual,
        _ => null,
      },
      provider: switch (raw['provider']) {
        'google_play' => BillingProvider.googlePlay,
        'app_store' => BillingProvider.appStore,
        'tap' => BillingProvider.tap,
        _ => null,
      },
      startedAt: _date(raw['started_at']),
      paidThrough: _date(raw['paid_through']),
      nextChargeAt: _date(raw['next_charge_at']),
      items: List.unmodifiable(items),
      testModeAvailable: testMode['available'] as bool,
      testScenario: scenario is String ? scenario : null,
      testExpiresAt: _date(testMode['expires_at']),
    );
  }

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;

  /// Whether a new item may be attempted in [section].
  QuotaDecision decideCreate(String section) {
    if (isPlus) return QuotaDecision.allowed;
    if (readOnly) return QuotaDecision.readOnly;
    final category = categoryOf(section);
    if (category == null) return QuotaDecision.unavailable;
    final used = created[category];
    if (used == null) return QuotaDecision.unavailable;
    return used >= SubscriptionPolicy.freeCreationsPerCategory
        ? QuotaDecision.limitReached
        : QuotaDecision.allowed;
  }

  /// [tapCardEligibilityVerified] comes only from the server's channel policy.
  SubscriptionPresentation toPresentation({
    bool tapCardEligibilityVerified = false,
  }) {
    final renewalPrice = switch (cycle) {
      PlusBillingCycle.monthly => SubscriptionPolicy.monthlyPrice,
      PlusBillingCycle.annual => SubscriptionPolicy.annualPrice,
      null => null,
    };
    final hasUsage = created.values.any((count) => count > 0);
    return SubscriptionPresentation(
      status: status,
      cycle: cycle,
      provider: provider,
      startedAt: startedAt,
      paidThrough: paidThrough,
      nextChargeAt: nextChargeAt,
      // A test entitlement has no price and no charge.
      renewalPrice: isTest ? null : renewalPrice,
      usage: UsageSnapshot(
        state: hasUsage ? UsageDataState.populated : UsageDataState.empty,
        created: created,
        items: items,
      ),
      tapCardEligibilityVerified: tapCardEligibilityVerified,
    );
  }
}
