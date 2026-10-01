import 'package:broker_wallet/src/data/models/subscription/subscription_ui_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SubscriptionStatus', () {
    test('only expired and free mean Plus is not the current plan', () {
      expect(SubscriptionStatus.free.isCurrentPlus, isFalse);
      expect(SubscriptionStatus.expired.isCurrentPlus, isFalse);
      for (final status in [
        SubscriptionStatus.trial,
        SubscriptionStatus.active,
        SubscriptionStatus.cancelledActive,
        SubscriptionStatus.gracePeriod,
        SubscriptionStatus.billingIssue,
      ]) {
        expect(status.isCurrentPlus, isTrue, reason: '$status');
      }
    });

    test('a payment problem never presents Plus as already lost', () {
      expect(SubscriptionStatus.gracePeriod.isCurrentPlus, isTrue);
      expect(SubscriptionStatus.billingIssue.isCurrentPlus, isTrue);
      expect(SubscriptionStatus.gracePeriod.needsPaymentAttention, isTrue);
      expect(SubscriptionStatus.billingIssue.needsPaymentAttention, isTrue);
      expect(SubscriptionStatus.active.needsPaymentAttention, isFalse);
    });

    test('a cancelled subscription is still current but no longer renews', () {
      expect(SubscriptionStatus.cancelledActive.isCurrentPlus, isTrue);
      expect(SubscriptionStatus.cancelledActive.autoRenews, isFalse);
      expect(SubscriptionStatus.active.autoRenews, isTrue);
      expect(SubscriptionStatus.trial.autoRenews, isTrue);
    });
  });

  group('SubscriptionPlanUiModel', () {
    test('charges the full billing-period price when one is supplied', () {
      const plan = SubscriptionPlanUiModel(
        id: 'annual',
        period: SubscriptionPeriod.annual,
        localizedPrice: 'EUR 4.17',
        fullBillingPeriodPrice: 'EUR 49.99',
      );
      expect(plan.chargedPerPeriod, 'EUR 49.99');
    });

    test('falls back to the headline price when there is no separate one', () {
      const plan = SubscriptionPlanUiModel(
        id: 'monthly',
        period: SubscriptionPeriod.monthly,
        localizedPrice: 'EUR 4.99',
      );
      expect(plan.chargedPerPeriod, 'EUR 4.99');
    });

    test('has a free trial from either a day count or store offer text', () {
      const none = SubscriptionPlanUiModel(
        id: 'a',
        period: SubscriptionPeriod.monthly,
        localizedPrice: 'x',
      );
      const days = SubscriptionPlanUiModel(
        id: 'b',
        period: SubscriptionPeriod.monthly,
        localizedPrice: 'x',
        freeTrialDays: 7,
      );
      const text = SubscriptionPlanUiModel(
        id: 'c',
        period: SubscriptionPeriod.monthly,
        localizedPrice: 'x',
        introductoryOfferText: '1 month free',
      );
      const blankText = SubscriptionPlanUiModel(
        id: 'd',
        period: SubscriptionPeriod.monthly,
        localizedPrice: 'x',
        introductoryOfferText: '   ',
      );
      expect(none.hasFreeTrial, isFalse);
      expect(days.hasFreeTrial, isTrue);
      expect(text.hasFreeTrial, isTrue);
      expect(blankText.hasFreeTrial, isFalse);
    });
  });

  group('SubscriptionOfferingUiModel', () {
    const monthly = SubscriptionPlanUiModel(
      id: 'm',
      period: SubscriptionPeriod.monthly,
      localizedPrice: 'x',
    );
    const annual = SubscriptionPlanUiModel(
      id: 'a',
      period: SubscriptionPeriod.annual,
      localizedPrice: 'y',
    );

    test('unavailable has no plans and no default', () {
      const offering = SubscriptionOfferingUiModel.unavailable();
      expect(offering.isAvailable, isFalse);
      expect(offering.defaultPlan, isNull);
    });

    test('defaults to the supplied preselection, else the first plan', () {
      expect(
        const SubscriptionOfferingUiModel(
          plans: [monthly, annual],
          preselectedPeriod: SubscriptionPeriod.annual,
        ).defaultPlan,
        annual,
      );
      expect(
        const SubscriptionOfferingUiModel(plans: [monthly, annual]).defaultPlan,
        monthly,
      );
    });

    test('ignores a preselection the offering does not contain', () {
      expect(
        const SubscriptionOfferingUiModel(
          plans: [monthly],
          preselectedPeriod: SubscriptionPeriod.annual,
        ).defaultPlan,
        monthly,
      );
    });

    test('works with a single plan', () {
      const offering = SubscriptionOfferingUiModel(plans: [annual]);
      expect(offering.isAvailable, isTrue);
      expect(offering.planFor(SubscriptionPeriod.monthly), isNull);
      expect(offering.planFor(SubscriptionPeriod.annual), annual);
    });
  });

  group('PurchasePhase', () {
    test('classifies progress, results and failures', () {
      for (final phase in [
        PurchasePhase.initiating,
        PurchasePhase.waitingForStore,
        PurchasePhase.verifying,
        PurchasePhase.finalizing,
      ]) {
        expect(phase.isInProgress, isTrue, reason: '$phase');
        expect(phase.isResult, isFalse, reason: '$phase');
        expect(phase.stepIndex, greaterThanOrEqualTo(0), reason: '$phase');
      }
      expect(PurchasePhase.idle.isInProgress, isFalse);
      expect(PurchasePhase.idle.isResult, isFalse);
      for (final phase in [
        PurchasePhase.success,
        PurchasePhase.pending,
        PurchasePhase.cancelled,
        PurchasePhase.storeProblem,
        PurchasePhase.networkProblem,
        PurchasePhase.verificationFailed,
        PurchasePhase.unknownFailure,
      ]) {
        expect(phase.isResult, isTrue, reason: '$phase');
        expect(phase.isInProgress, isFalse, reason: '$phase');
      }
    });

    test('success, pending and cancelled are not failures', () {
      expect(PurchasePhase.success.isFailure, isFalse);
      expect(PurchasePhase.pending.isFailure, isFalse);
      expect(PurchasePhase.cancelled.isFailure, isFalse);
      expect(PurchasePhase.storeProblem.isFailure, isTrue);
      expect(PurchasePhase.networkProblem.isFailure, isTrue);
      expect(PurchasePhase.verificationFailed.isFailure, isTrue);
      expect(PurchasePhase.unknownFailure.isFailure, isTrue);
    });

    test('the four progress steps are numbered in order', () {
      expect(PurchasePhase.initiating.stepIndex, 0);
      expect(PurchasePhase.waitingForStore.stepIndex, 1);
      expect(PurchasePhase.verifying.stepIndex, 2);
      expect(PurchasePhase.finalizing.stepIndex, 3);
    });
  });

  group('currentPlusStore', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('maps the platform to its store', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(currentPlusStore(), PlusStore.appStore);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(currentPlusStore(), PlusStore.googlePlay);
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(currentPlusStore(), PlusStore.unknown);
    });
  });

  group('RestorePhase', () {
    test('idle and restoring are not results', () {
      expect(RestorePhase.idle.isResult, isFalse);
      expect(RestorePhase.restoring.isResult, isFalse);
      expect(RestorePhase.restored.isResult, isTrue);
      expect(RestorePhase.unavailable.isResult, isTrue);
    });
  });
}
