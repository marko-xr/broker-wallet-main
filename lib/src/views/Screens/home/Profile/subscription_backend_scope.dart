import 'package:broker_wallet/src/config/supabase_config.dart';
import 'package:broker_wallet/src/viewmodels/subscription_state_controller.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_presentation.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_scope.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

/// Feeds the Profile subscription screens from the server-confirmed state.
/// With the subscription backend off it adds nothing, so they keep showing
/// the honest unavailable state.
class SubscriptionBackendScope extends StatelessWidget {
  const SubscriptionBackendScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!SupabaseConfig.subscriptionBackendEnabled) return child;
    return Selector<SubscriptionStateController, SubscriptionPresentation>(
      selector: (_, controller) => controller.presentation,
      builder: (_, presentation, scoped) =>
          SubscriptionScope(presentation: presentation, child: scoped!),
      child: child,
    );
  }
}

/// Asks the server again each time My Plan opens. Draws nothing.
class SubscriptionStateRefresher extends StatefulWidget {
  const SubscriptionStateRefresher({super.key});

  @override
  State<SubscriptionStateRefresher> createState() =>
      _SubscriptionStateRefresherState();
}

class _SubscriptionStateRefresherState
    extends State<SubscriptionStateRefresher> {
  @override
  void initState() {
    super.initState();
    if (!SupabaseConfig.subscriptionBackendEnabled) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SubscriptionStateController>().refresh();
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
