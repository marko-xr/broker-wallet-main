import 'package:broker_wallet/src/data/models/subscription/subscription_ui_models.dart';
import 'package:broker_wallet/src/services/subscription/debug_plus_billing_gateway.dart';
import 'package:broker_wallet/src/services/subscription/plus_billing_gateway.dart';
import 'package:broker_wallet/src/viewmodels/plus_subscription_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'plus_test_support.dart';

PlusSubscriptionViewModel _vm(FakePlusGateway gateway) {
  final vm = PlusSubscriptionViewModel(gateway: gateway);
  addTearDown(() async {
    vm.dispose();
    await gateway.dispose();
  });
  return vm;
}

Future<PlusSubscriptionViewModel> _ready(FakePlusGateway gateway) async {
  final vm = _vm(gateway);
  await vm.ensureOfferingLoaded();
  return vm;
}

void main() {
  group('offering', () {
    test('loads once and preselects the offering default', () async {
      final gateway = FakePlusGateway();
      final vm = _vm(gateway);
      expect(vm.offeringState, OfferingLoadState.idle);

      await vm.ensureOfferingLoaded();
      await vm.ensureOfferingLoaded();

      expect(gateway.loadCalls, 1);
      expect(vm.offeringState, OfferingLoadState.ready);
      expect(vm.selectedPlan, testAnnualPlan);
      expect(vm.selectedPeriod, SubscriptionPeriod.annual);
    });

    test('selecting a period changes the selected plan', () async {
      final vm = await _ready(FakePlusGateway());
      vm.selectPeriod(SubscriptionPeriod.monthly);
      expect(vm.selectedPlan, testMonthlyPlan);
    });

    test('ignores a period the offering does not contain', () async {
      final vm = await _ready(
        FakePlusGateway(
          offering: const SubscriptionOfferingUiModel(plans: [testAnnualPlan]),
        ),
      );
      vm.selectPeriod(SubscriptionPeriod.monthly);
      expect(vm.selectedPlan, testAnnualPlan);
    });

    test('no plans means unavailable and nothing selected', () async {
      final vm = await _ready(
        FakePlusGateway(
          offering: const SubscriptionOfferingUiModel.unavailable(),
        ),
      );
      expect(vm.offeringState, OfferingLoadState.unavailable);
      expect(vm.selectedPlan, isNull);
    });

    test('a loading failure becomes unavailable, not a thrown error', () async {
      final gateway = FakePlusGateway()..loadError = StateError('boom');
      final vm = await _ready(gateway);
      expect(vm.offeringState, OfferingLoadState.unavailable);
      expect(vm.offering.isAvailable, isFalse);
    });
  });

  group('purchase', () {
    test('does nothing without a selected plan', () async {
      final gateway = FakePlusGateway(
        offering: const SubscriptionOfferingUiModel.unavailable(),
      );
      final vm = await _ready(gateway);
      await vm.beginPurchase();
      expect(gateway.purchaseCalls, 0);
      expect(vm.purchasePhase, PurchasePhase.idle);
    });

    test('a confirmed purchase applies the reported entitlement', () async {
      final gateway = FakePlusGateway();
      final vm = await _ready(gateway);
      final done = vm.beginPurchase();

      expect(vm.purchasePhase, PurchasePhase.initiating);
      gateway.purchaseController!
        ..add(const PurchaseUpdate(PurchasePhase.waitingForStore))
        ..add(const PurchaseUpdate(PurchasePhase.verifying))
        ..add(PurchaseUpdate(PurchasePhase.success, entitlement: testActive()));
      await gateway.purchaseController!.close();
      await done;

      expect(vm.purchasePhase, PurchasePhase.success);
      expect(vm.status, SubscriptionStatus.active);
      expect(vm.hasPendingPurchase, isFalse);
    });

    test('success without an entitlement is never shown as success', () async {
      final gateway = FakePlusGateway();
      final vm = await _ready(gateway);
      final done = vm.beginPurchase();

      gateway.purchaseController!
          .add(const PurchaseUpdate(PurchasePhase.success));
      await gateway.purchaseController!.close();
      await done;

      expect(vm.purchasePhase, PurchasePhase.verificationFailed);
      expect(vm.status, SubscriptionStatus.free);
    });

    test('success with a non-Plus entitlement does not unlock either',
        () async {
      final gateway = FakePlusGateway();
      final vm = await _ready(gateway);
      final done = vm.beginPurchase();

      gateway.purchaseController!.add(
        PurchaseUpdate(
          PurchasePhase.success,
          entitlement: testState(SubscriptionStatus.expired),
        ),
      );
      await gateway.purchaseController!.close();
      await done;

      expect(vm.purchasePhase, PurchasePhase.verificationFailed);
      expect(vm.status, SubscriptionStatus.free);
    });

    test('a second begin while one is in progress is ignored', () async {
      final gateway = FakePlusGateway();
      final vm = await _ready(gateway);

      final first = vm.beginPurchase();
      final second = vm.beginPurchase();
      await second;

      expect(gateway.purchaseCalls, 1);
      await gateway.purchaseController!.close();
      await first;
    });

    test('pending is remembered for display but unlocks nothing', () async {
      final gateway = FakePlusGateway();
      final vm = await _ready(gateway);
      final done = vm.beginPurchase();

      gateway.purchaseController!
          .add(const PurchaseUpdate(PurchasePhase.pending));
      await gateway.purchaseController!.close();
      await done;

      expect(vm.purchasePhase, PurchasePhase.pending);
      expect(vm.hasPendingPurchase, isTrue);
      expect(vm.status, SubscriptionStatus.free);
    });

    test('cancel and every failure keep the user on Free', () async {
      for (final outcome in [
        PurchasePhase.cancelled,
        PurchasePhase.storeProblem,
        PurchasePhase.networkProblem,
        PurchasePhase.verificationFailed,
        PurchasePhase.unknownFailure,
      ]) {
        final gateway = FakePlusGateway();
        final vm = await _ready(gateway);
        final done = vm.beginPurchase();
        gateway.purchaseController!.add(PurchaseUpdate(outcome));
        await gateway.purchaseController!.close();
        await done;

        expect(vm.purchasePhase, outcome);
        expect(vm.status, SubscriptionStatus.free, reason: '$outcome');
        expect(vm.hasPendingPurchase, isFalse, reason: '$outcome');
      }
    });

    test('a source that ends without a result is an unknown failure', () async {
      final gateway = FakePlusGateway();
      final vm = await _ready(gateway);
      final done = vm.beginPurchase();
      await gateway.purchaseController!.close();
      await done;
      expect(vm.purchasePhase, PurchasePhase.unknownFailure);
      expect(vm.status, SubscriptionStatus.free);
    });

    test('a source that throws is an unknown failure, not an exception',
        () async {
      final gateway = FakePlusGateway();
      final vm = await _ready(gateway);
      final done = vm.beginPurchase();
      gateway.purchaseController!.addError(StateError('raw store error'));
      await done;
      expect(vm.purchasePhase, PurchasePhase.unknownFailure);
    });

    test('can try again after a failure', () async {
      final gateway = FakePlusGateway();
      final vm = await _ready(gateway);

      var done = vm.beginPurchase();
      gateway.purchaseController!
          .add(const PurchaseUpdate(PurchasePhase.networkProblem));
      await gateway.purchaseController!.close();
      await done;
      expect(vm.purchasePhase, PurchasePhase.networkProblem);

      done = vm.beginPurchase();
      expect(vm.purchasePhase, PurchasePhase.initiating);
      gateway.purchaseController!.add(
          PurchaseUpdate(PurchasePhase.success, entitlement: testActive()));
      await gateway.purchaseController!.close();
      await done;

      expect(gateway.purchaseCalls, 2);
      expect(vm.status, SubscriptionStatus.active);
    });

    test('acknowledging clears a finished result but not one in progress',
        () async {
      final gateway = FakePlusGateway();
      final vm = await _ready(gateway);
      final done = vm.beginPurchase();

      vm.acknowledgePurchaseResult();
      expect(vm.purchasePhase, PurchasePhase.initiating);

      gateway.purchaseController!
          .add(const PurchaseUpdate(PurchasePhase.cancelled));
      await gateway.purchaseController!.close();
      await done;
      vm.acknowledgePurchaseResult();
      expect(vm.purchasePhase, PurchasePhase.idle);
    });
  });

  group('restore', () {
    test('restoring an entitlement the source reports applies it', () async {
      final gateway = FakePlusGateway();
      final vm = _vm(gateway);
      final done = vm.restorePurchases();
      expect(vm.restorePhase, RestorePhase.restoring);

      gateway.restoreCompleter!.complete(
        RestoreResult(RestorePhase.restored, entitlement: testActive()),
      );
      await done;

      expect(vm.restorePhase, RestorePhase.restored);
      expect(vm.status, SubscriptionStatus.active);
    });

    test('restore never manufactures an entitlement', () async {
      final gateway = FakePlusGateway();
      final vm = _vm(gateway);
      final done = vm.restorePurchases();
      gateway.restoreCompleter!
          .complete(const RestoreResult(RestorePhase.restored));
      await done;

      expect(vm.restorePhase, RestorePhase.nothingFound);
      expect(vm.status, SubscriptionStatus.free);
    });

    test('nothing found, conflict, failure and unavailable change nothing',
        () async {
      for (final outcome in [
        RestorePhase.nothingFound,
        RestorePhase.conflict,
        RestorePhase.failed,
        RestorePhase.unavailable,
      ]) {
        final gateway = FakePlusGateway();
        final vm = _vm(gateway);
        final done = vm.restorePurchases();
        gateway.restoreCompleter!.complete(RestoreResult(outcome));
        await done;

        expect(vm.restorePhase, outcome);
        expect(vm.status, SubscriptionStatus.free, reason: '$outcome');
      }
    });

    test('a second restore while one is running is ignored', () async {
      final gateway = FakePlusGateway();
      final vm = _vm(gateway);
      final first = vm.restorePurchases();
      await vm.restorePurchases();
      expect(gateway.restoreCalls, 1);

      gateway.restoreCompleter!
          .complete(const RestoreResult(RestorePhase.nothingFound));
      await first;
    });

    test('resetRestore returns a finished restore to the start', () async {
      final gateway = FakePlusGateway();
      final vm = _vm(gateway);
      final done = vm.restorePurchases();
      gateway.restoreCompleter!
          .complete(const RestoreResult(RestorePhase.nothingFound));
      await done;

      vm.resetRestore();
      expect(vm.restorePhase, RestorePhase.idle);
    });
  });

  group('account scope', () {
    test('a different account starts again from Free', () async {
      final gateway = FakePlusGateway();
      final vm = _vm(gateway);
      vm.attachAccount('user-a');
      vm.applyEntitlement(testActive());
      expect(vm.status, SubscriptionStatus.active);

      vm.attachAccount('user-b');
      expect(vm.status, SubscriptionStatus.free);
      expect(vm.purchasePhase, PurchasePhase.idle);
      expect(vm.hasPendingPurchase, isFalse);
    });

    test('signing out clears the state too', () {
      final vm = _vm(FakePlusGateway());
      vm.attachAccount('user-a');
      vm.applyEntitlement(testActive());
      vm.attachAccount(null);
      expect(vm.status, SubscriptionStatus.free);
    });

    test('re-attaching the same account keeps the state', () {
      final vm = _vm(FakePlusGateway());
      vm.attachAccount('user-a');
      vm.applyEntitlement(testActive());
      vm.attachAccount('user-a');
      expect(vm.status, SubscriptionStatus.active);
    });

    test('an in-flight purchase cannot land on the next account', () async {
      final gateway = FakePlusGateway();
      final vm = await _ready(gateway);
      vm.attachAccount('user-a');
      final done = vm.beginPurchase();

      vm.attachAccount('user-b');
      gateway.purchaseController!.add(
          PurchaseUpdate(PurchasePhase.success, entitlement: testActive()));
      await gateway.purchaseController!.close();
      await done;

      expect(vm.status, SubscriptionStatus.free);
    });
  });

  group('entitlement from a source', () {
    test('applyEntitlement shows the state and clears a pending purchase', () {
      final vm = _vm(FakePlusGateway());
      vm.debugShowPurchasePhase(PurchasePhase.pending);
      expect(vm.hasPendingPurchase, isTrue);

      vm.applyEntitlement(testActive());
      expect(vm.status, SubscriptionStatus.active);
      expect(vm.hasPendingPurchase, isFalse);
    });

    test('the store of a known subscription wins over the device store', () {
      final vm = _vm(FakePlusGateway());
      vm.applyEntitlement(
        const SubscriptionUiState(
          status: SubscriptionStatus.active,
          store: PlusStore.appStore,
        ),
      );
      expect(vm.effectiveStore, PlusStore.appStore);
    });
  });

  group('unavailable gateway (every non-debug build)', () {
    test('offers nothing and cannot restore', () async {
      const gateway = UnavailablePlusBillingGateway();
      expect(gateway.isBillingAvailable, isFalse);
      expect((await gateway.loadOffering()).isAvailable, isFalse);
      expect(
        (await gateway.restorePurchases()).phase,
        RestorePhase.unavailable,
      );
    });

    test('the view model stays on Free and never offers a plan', () async {
      final vm = PlusSubscriptionViewModel(
        gateway: const UnavailablePlusBillingGateway(),
      );
      addTearDown(vm.dispose);
      await vm.ensureOfferingLoaded();
      await vm.beginPurchase();

      expect(vm.offeringState, OfferingLoadState.unavailable);
      expect(vm.selectedPlan, isNull);
      expect(vm.status, SubscriptionStatus.free);
      expect(vm.isBillingAvailable, isFalse);
      expect(vm.debugPreviewConfig, isNull);
    });
  });

  group('debug preview (debug builds only)', () {
    test('the preview gateway reports preview data, never real prices',
        () async {
      final gateway = DebugPlusBillingGateway(stepDelay: Duration.zero);
      final offering = await gateway.loadOffering();
      expect(offering.isPreview, isTrue);
      expect(offering.plans, hasLength(2));

      gateway.config.offeringMode = DebugOfferingMode.none;
      expect((await gateway.loadOffering()).isAvailable, isFalse);
    });

    test('a preview purchase walks the steps and ends in a preview state',
        () async {
      final gateway = DebugPlusBillingGateway(stepDelay: Duration.zero);
      final updates = await gateway.purchase(testAnnualPlan).toList();

      expect(
        updates.map((u) => u.phase),
        [
          PurchasePhase.initiating,
          PurchasePhase.waitingForStore,
          PurchasePhase.verifying,
          PurchasePhase.finalizing,
          PurchasePhase.success,
        ],
      );
      expect(updates.last.entitlement?.isPreview, isTrue);
    });

    test('a cancelled preview stops at the store sheet with no entitlement',
        () async {
      final gateway = DebugPlusBillingGateway(stepDelay: Duration.zero);
      gateway.config.purchaseOutcome = PurchasePhase.cancelled;
      final updates = await gateway.purchase(testAnnualPlan).toList();

      expect(
        updates.map((u) => u.phase),
        [
          PurchasePhase.initiating,
          PurchasePhase.waitingForStore,
          PurchasePhase.cancelled,
        ],
      );
      expect(updates.last.entitlement, isNull);
    });

    test('a pending preview carries no entitlement', () async {
      final gateway = DebugPlusBillingGateway(stepDelay: Duration.zero);
      gateway.config.purchaseOutcome = PurchasePhase.pending;
      final updates = await gateway.purchase(testAnnualPlan).toList();
      expect(updates.last.phase, PurchasePhase.pending);
      expect(updates.last.entitlement, isNull);
    });

    test('preview entitlements are always flagged as preview', () {
      for (final status in SubscriptionStatus.values) {
        final state = DebugPlusPreviewData.entitlementFor(status);
        expect(state.status, status);
        if (status != SubscriptionStatus.free) {
          expect(state.isPreview, isTrue, reason: '$status');
        }
      }
    });

    test('the preview chooser can show every state and reset', () async {
      final vm = _vm(FakePlusGateway());
      vm.debugApplyEntitlement(
        DebugPlusPreviewData.entitlementFor(SubscriptionStatus.cancelledActive),
      );
      expect(vm.status, SubscriptionStatus.cancelledActive);

      vm.debugShowPurchasePhase(PurchasePhase.verificationFailed);
      expect(vm.purchasePhase, PurchasePhase.verificationFailed);

      vm.debugShowRestorePhase(RestorePhase.conflict);
      expect(vm.restorePhase, RestorePhase.conflict);
      // A held preview result survives the restore screen opening.
      vm.resetRestore();
      expect(vm.restorePhase, RestorePhase.conflict);

      vm.debugReset();
      expect(vm.status, SubscriptionStatus.free);
      expect(vm.purchasePhase, PurchasePhase.idle);
      expect(vm.restorePhase, RestorePhase.idle);
    });

    test('the full preview purchase works end to end through the view model',
        () async {
      final gateway = DebugPlusBillingGateway(stepDelay: Duration.zero);
      final vm = PlusSubscriptionViewModel(gateway: gateway);
      addTearDown(vm.dispose);

      await vm.ensureOfferingLoaded();
      await vm.beginPurchase();

      expect(vm.purchasePhase, PurchasePhase.success);
      expect(vm.status, SubscriptionStatus.active);
      expect(vm.entitlement.isPreview, isTrue);
    });

    test('the preview can show either store, but a subscription pins its own',
        () {
      final vm = _vm(FakePlusGateway());
      vm.debugSetStore(PlusStore.appStore);
      expect(vm.effectiveStore, PlusStore.appStore);
      vm.debugSetStore(PlusStore.googlePlay);
      expect(vm.effectiveStore, PlusStore.googlePlay);

      vm.applyEntitlement(
        const SubscriptionUiState(
          status: SubscriptionStatus.active,
          store: PlusStore.appStore,
        ),
      );
      expect(vm.effectiveStore, PlusStore.appStore);

      vm.debugReset();
      expect(vm.debugStore, isNull);
    });

    test('preview states carry prices only where a charge or plan applies', () {
      final active = DebugPlusPreviewData.entitlementFor(
        SubscriptionStatus.active,
        store: PlusStore.appStore,
      );
      expect(active.store, PlusStore.appStore);
      expect(active.billingPeriodPrice, DebugPlusPreviewData.annualPrice);
      expect(active.nextChargePrice, DebugPlusPreviewData.annualPrice);

      final cancelled = DebugPlusPreviewData.entitlementFor(
        SubscriptionStatus.cancelledActive,
      );
      expect(cancelled.billingPeriodPrice, isNotNull);
      expect(cancelled.nextChargePrice, isNull,
          reason: 'renewal is off, so nothing will be charged');

      final expired = DebugPlusPreviewData.entitlementFor(
        SubscriptionStatus.expired,
      );
      expect(expired.billingPeriodPrice, isNull);
      expect(expired.nextChargePrice, isNull);
    });
  });
}
