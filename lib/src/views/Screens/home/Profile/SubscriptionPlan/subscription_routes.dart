import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/cancellation_info_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/how_limits_work_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/manage_subscription_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/live_restore_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/plan_compare_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/play_checkout_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/restore_purchases_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_flow_state_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_presentation.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_preview_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/tap_checkout_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/usage_details_view.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

/// The Profile subscription module's own routes. The preview routes exist in
/// debug builds only, and only they may pass a designed state through `extra`.
List<GoRoute> subscriptionProfileRoutes() => [
      GoRoute(
        path: SubscriptionRoutes.limits,
        builder: (context, state) => const HowLimitsWorkView(),
      ),
      GoRoute(
        path: SubscriptionRoutes.compare,
        builder: (context, state) => const PlanCompareView(),
      ),
      GoRoute(
        path: SubscriptionRoutes.usage,
        builder: (context, state) => const UsageDetailsView(),
      ),
      GoRoute(
        path: SubscriptionRoutes.manage,
        builder: (context, state) => const ManageSubscriptionView(),
      ),
      GoRoute(
        path: SubscriptionRoutes.cancellation,
        builder: (context, state) => const CancellationInfoView(),
      ),
      GoRoute(
        path: SubscriptionRoutes.restore,
        builder: (context, state) {
          final extra = state.extra;
          if (kDebugMode && extra is RestorePurchaseState) {
            return RestorePurchasesView(state: extra);
          }
          return canRestoreLive()
              ? const LiveRestoreView()
              : const RestorePurchasesView();
        },
      ),
      GoRoute(
        path: SubscriptionRoutes.playCheckout,
        builder: (context, state) => PlayCheckoutView(
          cycle: state.uri.queryParameters['cycle'] == 'monthly'
              ? PlusBillingCycle.monthly
              : PlusBillingCycle.annual,
        ),
      ),
      // Each screen re-checks the platform policy, so a typed or linked address
      // cannot open a payment where the policy does not allow one.
      GoRoute(
        path: SubscriptionRoutes.checkout,
        builder: (context, state) => TapCheckoutView.pay(
          cycle: state.uri.queryParameters['cycle'] == 'monthly'
              ? PlusBillingCycle.monthly
              : PlusBillingCycle.annual,
        ),
      ),
      GoRoute(
        path: SubscriptionRoutes.changeCard,
        builder: (context, state) => const TapCheckoutView.changeCard(),
      ),
      GoRoute(
        path: SubscriptionRoutes.paymentReturn,
        builder: (context, state) => const TapCheckoutView.returning(),
      ),
      if (kDebugMode) ...[
        GoRoute(
          path: SubscriptionRoutes.preview,
          builder: (context, state) => const SubscriptionPreviewView(),
        ),
        GoRoute(
          path: SubscriptionRoutes.flowState,
          builder: (context, state) {
            final extra = state.extra;
            if (extra is PaymentReviewRequest) {
              return SubscriptionFlowStateView(
                state: SubscriptionFlowState.purchaseReview,
                request: extra,
              );
            }
            return SubscriptionFlowStateView(
              state: extra is SubscriptionFlowState
                  ? extra
                  : SubscriptionFlowState.verificationFailed,
            );
          },
        ),
      ],
    ];
