import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/data/models/unified_item_model.dart';
import 'package:broker_wallet/src/data/models/filter_model.dart';
import 'package:broker_wallet/src/viewmodels/home_filter_controller.dart';
import 'package:broker_wallet/src/viewmodels/home_viewmodel.dart';
import 'package:broker_wallet/src/Views/Widgets/filtered_tiles.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/brokers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offices_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/watchmen_model.dart';

class FilteredItemsView extends StatelessWidget {
  const FilteredItemsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<HomeViewModel>(
      builder: (context, vm, _) {
        final localization = AppLocalizations.of(context);
        final theme = Theme.of(context);
        final selectedFilter = vm.selectedFilter;

        // Show loading indicator ONLY when explicitly loading
        if (vm.isFilterLoading) {
          return _buildLoadingState(context, theme);
        }

        // A chip whose filter is not built yet says so; it is never shown as
        // "no items", which would claim the filter ran.
        if (vm.isFilterUnavailable) {
          return _buildComingSoonState(context, localization, theme);
        }

        // A filter that could not be answered says so and offers a retry; it is
        // never shown as "no items".
        final errorKind = vm.filterErrorKind;
        if (errorKind != null) {
          return _buildErrorState(
              context, localization, theme, errorKind, vm.retryFilter);
        }

        // Show empty state if no filter selected OR if filter is selected but no items found
        if (selectedFilter == null || vm.filteredItems.isEmpty) {
          return _buildEmptyState(context, localization, theme);
        }

        return _buildFilteredItemsList(
            context, vm, localization, theme, selectedFilter);
      },
    );
  }

  Widget _buildLoadingState(BuildContext context, ThemeData theme) {
    final localization = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(
                theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              localization.translate('loadingFilteredItems'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// What to tell the person about a filter that could not be answered, from
  /// strings the app already has. The technical error is never shown.
  static String errorMessage(AppLocalizations loc, HomeFilterErrorKind kind) {
    switch (kind) {
      case HomeFilterErrorKind.network:
        return loc.translate('authNetworkFailed');
      case HomeFilterErrorKind.session:
        return loc.translate('userSessionExpired');
      case HomeFilterErrorKind.generic:
        return loc.translate('errorOccurred');
    }
  }

  Widget _buildErrorState(
    BuildContext context,
    AppLocalizations loc,
    ThemeData theme,
    HomeFilterErrorKind kind,
    VoidCallback onRetry,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(errorMessage(loc, kind),
                style: theme.textTheme.bodyLarge, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              child: Text(loc.translate('tryAgain')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComingSoonState(
      BuildContext context, AppLocalizations loc, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hourglass_top_rounded,
                size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(loc.translate('homeFilterComingSoonTitle'),
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: theme.colorScheme.outline),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(loc.translate('homeFilterComingSoonDesc'),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.outline),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(
      BuildContext context, AppLocalizations loc, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.filter_list_off,
                size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(loc.translate('noFilteredItems'),
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: theme.colorScheme.outline),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(loc.translate('noFilteredItemsDesc'),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.outline),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildFilteredItemsList(
    BuildContext context,
    HomeViewModel vm,
    AppLocalizations localization,
    ThemeData theme,
    FilterModel selectedFilter,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ListView.builder(
            // Pulling to refresh must work however few records the filter found.
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 96),
            itemCount: vm.filteredItems.length,
            itemBuilder: (context, index) {
              final item = vm.filteredItems[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: _buildFilteredItemCard(context, item, localization, theme),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFilteredItemCard(
    BuildContext context,
    UnifiedItemModel item,
    AppLocalizations localization,
    ThemeData theme,
  ) {
    // Use specialized tiles based on item type for consistency with list views
    switch (item.type) {
      case ItemType.offer:
        return FilteredOfferTile(
          offer: item.originalModel as OfferModel,
          localization: localization,
          index: 0,
          createdAt: item.createdAt,
        );
      case ItemType.request:
        return FilteredRequestTile(
          request: item.originalModel as RequestModel,
          localization: localization,
          index: 0,
          createdAt: item.createdAt,
        );
      case ItemType.broker:
        return FilteredBrokerTile(
          broker: item.originalModel as BrokerModel,
          localization: localization,
          index: 0,
          createdAt: item.createdAt,
        );
      case ItemType.owner:
        return FilteredOwnerTile(
          owner: item.originalModel as OwnerModel,
          localization: localization,
          index: 0,
          createdAt: item.createdAt,
        );
      case ItemType.office:
        return FilteredOfficeTile(
          office: item.originalModel as OfficeModel,
          localization: localization,
          index: 0,
          createdAt: item.createdAt,
        );
      case ItemType.watchmen:
        return FilteredWatchmenTile(
          watchmen: item.originalModel as WatchmenModel,
          localization: localization,
          index: 0,
          createdAt: item.createdAt,
        );
      case ItemType.quotation:
        // Quotations are not part of the Home filters (HomeFilterRules drops
        // them), and there is no tile for them here. Draw nothing rather than
        // crash if one ever arrives.
        return const SizedBox.shrink();
    }
  }
}
