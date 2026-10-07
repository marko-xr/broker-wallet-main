import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:broker_wallet/src/Views/Widgets/home_filter_chips.dart';
import 'package:broker_wallet/src/Views/Widgets/grid_item_card.dart';
import 'package:broker_wallet/src/Views/Widgets/filtered_items_view.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/views/Widgets/user_screen_header.dart';
import '../../viewmodels/home_viewmodel.dart';

class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<HomeViewModel>(
      builder: (context, vm, _) {
        final theme = Theme.of(context);
        final localization = AppLocalizations.of(context);

        return Scaffold(
          backgroundColor: theme.colorScheme.surface,
          body: SafeArea(
            bottom: false,
            child: RefreshIndicator(
              onRefresh: () async {
                // A pull refreshes what the screen shows, so a chosen filter
                // stays chosen and is read again with the counts.
                await vm.refreshCounts(keepFilter: true);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    UserScreenHeader(
                      subtitle: localization.translate('welcomeMessage'),
                    ),
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
}
