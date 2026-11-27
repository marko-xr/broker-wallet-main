import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_platform_policy.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_presentation.dart';

extension SubscriptionLabels on AppLocalizations {
  String fill(String key, Map<String, String> values) {
    var text = translate(key);
    values.forEach((name, value) {
      text = text.replaceAll('{$name}', value);
    });
    return text;
  }

  String aed(PlanPrice price) =>
      price.storeLabel ?? fill('subPriceAed', {'amount': price.amount});

  String perYear(PlanPrice price) => fill('subPerYear', {'price': aed(price)});

  String perMonth(PlanPrice price) =>
      fill('subPerMonth', {'price': aed(price)});

  String cyclePrice(PlusBillingCycle cycle, PlanPrice price) =>
      cycle == PlusBillingCycle.annual ? perYear(price) : perMonth(price);

  /// Day and year keep Western digits in both languages, as in the design.
  String shortDate(DateTime date) {
    final months = translate('subMonthsShort').split(',');
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String categoryName(UsageCategory category) => translate(switch (category) {
        UsageCategory.owners => 'subCatOwners',
        UsageCategory.offers => 'subCatOffers',
        UsageCategory.requests => 'subCatRequests',
        UsageCategory.watchmen => 'subCatWatchmen',
        UsageCategory.offices => 'subCatOffices',
        UsageCategory.brokers => 'subCatBrokers',
        UsageCategory.quotations => 'subCatQuotations',
        UsageCategory.scanner => 'subCatScanner',
        UsageCategory.signature => 'subCatSignature',
        UsageCategory.imagesToPdf => 'subCatImagesToPdf',
        UsageCategory.combinePdfs => 'subCatCombinePdfs',
      });

  String categoryList(Iterable<UsageCategory> categories) =>
      categories.map(categoryName).join(translate('subListSeparator'));

  String cycleName(PlusBillingCycle cycle) => translate(
      cycle == PlusBillingCycle.annual ? 'subCycleAnnual' : 'subCycleMonthly');

  /// Tap is named only where the platform policy allows it.
  String providerName(BillingProvider provider) => translate(switch (provider) {
        BillingProvider.appStore => 'subProviderAppStore',
        BillingProvider.googlePlay => 'subProviderGooglePlay',
        BillingProvider.tap => SubscriptionPlatformPolicy.hidesProvider(
                SubscriptionPlatformPolicy.current, provider)
            ? 'subProviderOther'
            : 'subProviderTap',
      });

  String paymentProviderName(PaymentOption option) =>
      translate(option == PaymentOption.googlePlay
          ? 'subProviderGooglePlay'
          : 'subPayCardTap');

  String plusWithCycle(SubscriptionPresentation p) {
    final cycle = p.cycle;
    if (cycle == null) return translate('subPlanPlus');
    return fill('subPlusWithCycle', {'cycle': cycleName(cycle)});
  }

  /// One-line plan status for the Profile summary and headers.
  String planLine(SubscriptionPresentation p) {
    switch (p.status) {
      case SubscriptionStatus.loading:
        return translate('subStatusChecking');
      case SubscriptionStatus.unavailable:
        return translate('planStatusUnavailable');
      case SubscriptionStatus.offline:
        return translate('subStatusOffline');
      case SubscriptionStatus.free:
        return translate('subPlanFree');
      case SubscriptionStatus.plusRenewing:
        final date = p.nextChargeAt ?? p.paidThrough;
        if (date == null) return plusWithCycle(p);
        return fill('subLineRenews',
            {'plan': plusWithCycle(p), 'date': shortDate(date)});
      case SubscriptionStatus.plusCancelScheduled:
        final date = p.paidThrough;
        if (date == null) return translate('subLineAutoRenewOff');
        return fill('subLineActiveUntil', {'date': shortDate(date)});
      case SubscriptionStatus.paymentIssue:
        return translate('subLinePaymentIssue');
      case SubscriptionStatus.activationPending:
        return translate('subLineActivationPending');
      case SubscriptionStatus.expiredOverLimit:
        return translate('subLineExpiredReadOnly');
      case SubscriptionStatus.expiredWithinFree:
        return translate('subLineBackOnFree');
    }
  }

  /// The status value on Billing, without repeating the plan or its dates.
  String billingStatus(SubscriptionPresentation p) => switch (p.status) {
        SubscriptionStatus.plusRenewing => translate('subAutoRenewOn'),
        SubscriptionStatus.plusCancelScheduled => translate('subAutoRenewOff'),
        SubscriptionStatus.paymentIssue => translate('subPillPaymentIssue'),
        SubscriptionStatus.activationPending => translate('subPillPending'),
        SubscriptionStatus.expiredOverLimit ||
        SubscriptionStatus.expiredWithinFree =>
          translate('subPillExpired'),
        SubscriptionStatus.free => translate('subPlanFree'),
        SubscriptionStatus.loading ||
        SubscriptionStatus.unavailable ||
        SubscriptionStatus.offline =>
          translate('subPillUnknown'),
      };

  String billingLine(SubscriptionPresentation p) {
    final provider = p.provider;
    if (p.isUnconfirmed || provider == null) {
      return translate('subBillingNotConnected');
    }
    if (SubscriptionPlatformPolicy.hidesProvider(
        SubscriptionPlatformPolicy.current, provider)) {
      return translate('subManagedNotHereShort');
    }
    return fill('subBillingThrough', {'provider': providerName(provider)});
  }

  /// A device that must not name the provider gets no "check it there" line.
  String paymentIssueBody(SubscriptionPresentation p) =>
      SubscriptionPlatformPolicy.hidesProvider(
        SubscriptionPlatformPolicy.current,
        p.provider,
      )
          ? translate('subPaymentIssueNeutral')
          : fill('subPaymentIssueBody', {'store': storeName(p)});

  /// The store name when known, otherwise a neutral "your app store".
  String storeName(SubscriptionPresentation p) {
    final provider = p.provider;
    return provider == null
        ? translate('subYourAppStore')
        : providerName(provider);
  }
}
