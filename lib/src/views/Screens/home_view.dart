import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:broker_wallet/src/Views/Widgets/home_filter_chips.dart';
import 'package:broker_wallet/src/Views/Widgets/grid_item_card.dart';
import 'package:broker_wallet/src/Views/Widgets/notification_icon.dart';
import 'package:broker_wallet/src/Views/Widgets/filtered_items_view.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/Views/Widgets/current_user_avatar.dart';
import '../../viewmodels/home_viewmodel.dart';
import '../../viewmodels/Signup-Login/auth_viewmodel.dart';

class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<HomeViewModel, AuthViewModel>(
      builder: (context, vm, authVM, _) {
        final theme = Theme.of(context);
        final localization = AppLocalizations.of(context);

        return Scaffold(
          backgroundColor: theme.colorScheme.surface,
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: () async {
                await vm.refreshCounts();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    _buildHeader(context, localization, authVM),
                    const SizedBox(height: 24),
                    HomeFilterChips(
                      filters: vm.filters,
                      onToggle: vm.toggleFilter,
                    ),
                    const SizedBox(height: 24),
                    Expanded(
                        child: vm.selectedFilter != null
                            ? const FilteredItemsView()
                            : GridItemCard.list(context, vm.items)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, AppLocalizations localization,
      AuthViewModel authVM) {
    final textTheme = Theme.of(context).textTheme;
    final resolvedName = authVM.displayName.trim();
    final userName = resolvedName.isNotEmpty
        ? resolvedName
        : localization.translate('favoritesGuestUser');

    return Row(
      children: [
        CurrentUserAvatar(
          size: 48,
          onTap: () => context.push('/edit-profile'),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: () => context.push('/edit-profile'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${localization.translate('hiGreeting')} $userName',
                  style: textTheme.headlineSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  localization.translate('welcomeMessage'),
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ),
        const NotificationIcon(),
      ],
    );
  }
}
