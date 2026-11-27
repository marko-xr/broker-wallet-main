import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_presentation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Supplies the subscription presentation to the Profile module. Production
/// installs no scope, so every screen receives the honest unavailable state.
class SubscriptionScope extends InheritedWidget {
  const SubscriptionScope({
    super.key,
    required this.presentation,
    required super.child,
  });

  final SubscriptionPresentation presentation;

  /// Set only by the debug state preview. Ignored outside debug builds.
  static SubscriptionPresentation? debugPreview;

  static SubscriptionPresentation of(BuildContext context) {
    if (kDebugMode && debugPreview != null) return debugPreview!;
    return context
            .dependOnInheritedWidgetOfExactType<SubscriptionScope>()
            ?.presentation ??
        const SubscriptionPresentation.unavailable();
  }

  @override
  bool updateShouldNotify(SubscriptionScope oldWidget) =>
      presentation != oldWidget.presentation;
}
