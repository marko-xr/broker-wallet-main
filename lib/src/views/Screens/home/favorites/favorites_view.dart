import 'dart:math' as math;

import 'package:broker_wallet/src/Views/Widgets/empty_state.dart';
import 'package:broker_wallet/src/views/Widgets/list_loading_indicator.dart'
    show DelayedReveal;
import 'package:broker_wallet/src/views/Widgets/user_screen_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:provider/provider.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/utils/svg_icon.dart';
import 'package:broker_wallet/src/Views/Screens/home/favorites/favorites_viewmodel.dart';
import 'package:broker_wallet/src/Views/Screens/home/favorites/favorites_filter_chips.dart';
import 'package:broker_wallet/src/Views/Screens/home/favorites/favorites_card.dart';
import 'package:broker_wallet/src/Views/Screens/home/favorites/favorites_item_model.dart';
import 'package:broker_wallet/src/Views/Screens/home/search/widgets/image_cache_manager.dart';
import 'package:broker_wallet/src/Views/Screens/home/search/widgets/search_result_card.dart'
    show SearchResultCard;
import 'package:broker_wallet/src/services/optimistic_favorites_service.dart';

// The page is laid out the way Search's results are: the same header, flat
// pinned filter chips on the page's own colour, the same two-column grid with
// the same spacing and card shape.
const int _gridColumns = 2;
const double _gridSpacing = 12;
const double _gridCardAspectRatio = 0.75;
const EdgeInsetsDirectional _gridPadding =
    EdgeInsetsDirectional.fromSTEB(16, 8, 16, 96);

/// The cards' grid. The shape stays 3 : 4 unless the text needs more room: a
/// favorite card is laid out exactly like a Search result card (its three
/// one-line fields sit in a fixed band), so it needs the same minimum height,
/// and a fixed shape would cut the third field off on a narrow phone or at a
/// large system font.
SliverGridDelegate _favoritesGridDelegate(
  BuildContext context,
  double crossAxisExtent,
) {
  final cardWidth = (crossAxisExtent - _gridSpacing) / _gridColumns;
  final extent = math.max(
    cardWidth / _gridCardAspectRatio,
    SearchResultCard.minHeightForText(context),
  );
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: _gridColumns,
    crossAxisSpacing: _gridSpacing,
    mainAxisSpacing: _gridSpacing,
    mainAxisExtent: extent,
  );
}

class FavoritesView extends StatelessWidget {
  const FavoritesView({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => FavoritesViewModel(
        optimisticFavoritesService:
            Provider.of<OptimisticFavoritesService>(context, listen: false),
      ),
      child: Consumer2<FavoritesViewModel, OptimisticFavoritesService>(
        builder: (context, vm, optimisticService, _) {
          final localization = AppLocalizations.of(context);

          vm.updateLocalization(localization);

          final slivers = <Widget>[
            // Header. It listens to the profile itself, so a profile update
            // does not rebuild the list.
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 12),
                child: UserScreenHeader(
                  subtitle: localization.translate('favoritesOverviewTitle'),
                ),
              ),
            ),
            _buildFilterBar(context, vm),
            ..._buildBodySlivers(context, vm, localization),
          ];

          return SafeArea(
            bottom: false,
            child: RefreshIndicator(
              onRefresh: vm.refresh,
              color: Theme.of(context).colorScheme.primary,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                scrollCacheExtent: const ScrollCacheExtent.pixels(1200),
                slivers: slivers,
              ),
            ),
          );
        },
      ),
    );
  }

  /// The filters. Pinned, so they stay reachable, but nothing is drawn behind
  /// them: no panel, no shadow, no tint. The bar is the page's own colour, so
  /// the chips float on the page and the cards simply scroll away under them.
  Widget _buildFilterBar(BuildContext context, FavoritesViewModel vm) {
    return SliverAppBar(
      pinned: true,
      automaticallyImplyLeading: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      toolbarHeight: FavoriteFilterChips.rowHeightOf(context),
      flexibleSpace: Align(
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
          child: FavoriteFilterChips(
            filters: vm.filters,
            onToggle: vm.toggleFilter,
          ),
        ),
      ),
    );
  }

  List<Widget> _buildBodySlivers(BuildContext context, FavoritesViewModel vm,
      AppLocalizations localization) {
    if (vm.isLoading && vm.cachedFavorites.isEmpty) {
      return [_buildLoadingInfoSliver(context, localization)];
    }

    if (vm.error != null && vm.cachedFavorites.isEmpty) {
      return [_buildErrorSliver(context, vm, localization)];
    }

    if (vm.hasNoFavorites && vm.cachedFavorites.isEmpty) {
      return [_buildEmptySliver(localization)];
    }

    if (vm.displayFavorites.isEmpty && vm.hasUnfilteredData) {
      return [_buildFilteredEmptySliver(localization, vm)];
    }

    return [
      _OptimizedFavoritesGrid(
        favorites: vm.displayFavorites,
        isLoadingMore: vm.isRefreshing,
        onRemoveFromFavorites: vm.removeFavorite,
      ),
      SliverToBoxAdapter(child: _buildRefreshHint(context, localization)),
    ];
  }

  Widget _buildRefreshHint(
      BuildContext context, AppLocalizations localization) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      // The foot of the list: 56 dp of room, so the docked add button, which
      // rises about 28 dp into the page, never covers the hint.
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 56),
      child: Text(
        localization.translate('favoritesRefreshHint'),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.onSurface.withValues(alpha: 0.6),
            ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildLoadingInfoSliver(
      BuildContext context, AppLocalizations localization) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return SliverToBoxAdapter(
      // Shown only if the first load is slow; a quick one never flashes it.
      child: DelayedReveal(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 56),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                localization.translate('favoritesLoadingPrimary'),
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                localization.translate('favoritesLoadingSecondary'),
                style: textTheme.bodyMedium?.copyWith(
                  color: colors.onSurface.withValues(alpha: 0.65),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A failure says so in the app's own words and offers a retry, as Search
  /// does. The technical error is never shown.
  Widget _buildErrorSliver(BuildContext context, FavoritesViewModel vm,
      AppLocalizations localization) {
    final colors = Theme.of(context).colorScheme;

    return SliverFillRemaining(
      hasScrollBody: false,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: colors.error),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              localization.translate('favoritesErrorTitle'),
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              vm.refresh();
            },
            child: Text(
              localization.translate('favoritesErrorAction'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptySliver(AppLocalizations localization) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: EmptyState(
          asset: SvgIcon.markedFavorite,
          title: localization.translate('noFavoritesYet'),
          subtitle: localization.translate('tapHeartToSave'),
        ),
      ),
    );
  }

  /// A filter that hides every favorite can be cleared from here, without
  /// hunting for its chip, as on Search.
  Widget _buildFilteredEmptySliver(
      AppLocalizations localization, FavoritesViewModel vm) {
    final selectedFilter = vm.selectedFilter;
    final filterLabel = selectedFilter != null
        ? (selectedFilter.labelKey != null
            ? localization.translate(selectedFilter.labelKey!)
            : selectedFilter.label)
        : localization.translate('favoritesFilterEmptyFallback');
    final titlePrefix =
        localization.translate('favoritesFilterEmptyTitlePrefix');

    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              EmptyState(
                asset: SvgIcon.markedFavorite,
                title: '$titlePrefix $filterLabel',
                subtitle:
                    localization.translate('favoritesFilterEmptySubtitle'),
              ),
              if (selectedFilter != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () =>
                      vm.toggleFilter(vm.filters.indexOf(selectedFilter)),
                  child: Text(localization.translate('clearFilter')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Optimized grid with prefetching and stable rebuilds
class _OptimizedFavoritesGrid extends StatefulWidget {
  final List<FavoriteItem> favorites;
  final bool isLoadingMore;
  final Function(FavoriteItem) onRemoveFromFavorites;

  const _OptimizedFavoritesGrid({
    required this.favorites,
    this.isLoadingMore = false,
    required this.onRemoveFromFavorites,
  });

  @override
  State<_OptimizedFavoritesGrid> createState() =>
      _OptimizedFavoritesGridState();
}

class _OptimizedFavoritesGridState extends State<_OptimizedFavoritesGrid>
    with AutomaticKeepAliveClientMixin<_OptimizedFavoritesGrid> {
  final ImageCacheManager _imageCache = ImageCacheManager();

  @override
  void initState() {
    super.initState();
    // Prefetch first batch of images immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prefetchVisibleImages();
    });
  }

  @override
  void didUpdateWidget(_OptimizedFavoritesGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Prefetch when favorites change
    if (widget.favorites != oldWidget.favorites) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _prefetchVisibleImages();
      });
    }
  }

  void _prefetchVisibleImages() {
    if (!mounted) return;

    // Get image URLs from first 6-8 visible items
    final visibleImageUrls = widget.favorites
        .take(8)
        .where((favorite) =>
            favorite.imageUrl != null && favorite.imageUrl!.isNotEmpty)
        .map((favorite) => favorite.imageUrl!)
        .toList();

    _imageCache.prefetchImages(context, visibleImageUrls);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SliverPadding(
      padding: _gridPadding,
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) => SliverGrid(
          gridDelegate:
              _favoritesGridDelegate(context, constraints.crossAxisExtent),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final favorite = widget.favorites[index];

              if (index == widget.favorites.length - 4) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _prefetchNextBatch(index);
                });
              }

              return FavoriteCard(
                key: ValueKey('${favorite.type}_${favorite.id}'),
                favorite: favorite,
                onRemoveFromFavorites: () =>
                    widget.onRemoveFromFavorites(favorite),
              );
            },
            childCount: widget.favorites.length,
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: true,
          ),
        ),
      ),
    );
  }

  void _prefetchNextBatch(int currentIndex) {
    if (!mounted) return;

    final nextBatchStart = currentIndex + 1;
    final nextBatchEnd = (nextBatchStart + 6).clamp(0, widget.favorites.length);

    final nextImageUrls = widget.favorites
        .getRange(nextBatchStart, nextBatchEnd)
        .where((favorite) =>
            favorite.imageUrl != null && favorite.imageUrl!.isNotEmpty)
        .map((favorite) => favorite.imageUrl!)
        .toList();

    _imageCache.prefetchImages(context, nextImageUrls, maxConcurrent: 2);
  }

  @override
  bool get wantKeepAlive => true;
}
