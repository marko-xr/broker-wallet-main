import 'package:flutter/material.dart';

/// One row of the Free-versus-Plus comparison.
///
/// Every entry has to be something Broker Wallet actually defines today. The
/// current definition is the free-plan creation limit (see `QuotaHelper`:
/// three items per section and three per Toolkit tool). Anything the app does
/// not yet offer — priority support, analytics, report export — is
/// deliberately *not* listed, and unfinished sections are not named, so the
/// paywall cannot advertise what is not there. Add a row here only together
/// with the feature it promises.
class PlusComparisonItem {
  const PlusComparisonItem({
    required this.icon,
    required this.titleKey,
    required this.bodyKey,
    required this.freeKey,
    required this.plusKey,
  });

  final IconData icon;
  final String titleKey;
  final String bodyKey;
  final String freeKey;
  final String plusKey;
}

class PlusCatalog {
  const PlusCatalog._();

  static const List<PlusComparisonItem> comparison = [
    PlusComparisonItem(
      icon: Icons.all_inclusive_rounded,
      titleKey: 'plusBenefitRecordsTitle',
      bodyKey: 'plusBenefitRecordsBody',
      freeKey: 'upToThreeItemsPerSection',
      plusKey: 'unlimited',
    ),
    PlusComparisonItem(
      icon: Icons.build_circle_outlined,
      titleKey: 'plusBenefitToolkitTitle',
      bodyKey: 'plusBenefitToolkitBody',
      freeKey: 'plusFreeToolkitLimit',
      plusKey: 'unlimited',
    ),
    PlusComparisonItem(
      icon: Icons.check_circle_outline_rounded,
      titleKey: 'plusBenefitEverythingTitle',
      bodyKey: 'plusBenefitEverythingBody',
      freeKey: 'plusIncluded',
      plusKey: 'plusIncluded',
    ),
  ];

  /// Short benefit lines for compact surfaces (purchase review, upgrade
  /// sheet). A subset of [comparison]; only what Plus adds over Free.
  static const List<String> highlightKeys = [
    'plusHighlightRecords',
    'plusHighlightToolkit',
  ];
}
