import 'dart:math' as math;

import 'package:broker_wallet/src/Views/Widgets/empty_state.dart';
import 'package:broker_wallet/src/Views/Widgets/current_user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/utils/svg_icon.dart';
import '../../../../viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:broker_wallet/src/Views/Screens/home/favorites/favorites_viewmodel.dart';
import 'package:broker_wallet/src/Views/Screens/home/favorites/favorites_filter_chips.dart';
import 'package:broker_wallet/src/Views/Widgets/notification_icon.dart';
import 'package:broker_wallet/src/Views/Screens/home/favorites/favorites_card.dart';
import 'package:broker_wallet/src/Views/Screens/home/favorites/favorites_item_model.dart';
import 'package:broker_wallet/src/Views/Screens/home/search/widgets/image_cache_manager.dart';
import 'package:broker_wallet/src/Views/Screens/home/search/widgets/search_result_card.dart'
    show SearchResultCard;
import 'package:broker_wallet/src/services/optimistic_favorites_service.dart';
import 'package:intl/intl.dart';

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

String _formatCount(int value, AppLocalizations localization) {
  final locale = localization.locale;
  final localeCode =
      (locale.countryCode != null && locale.countryCode!.isNotEmpty)
          ? '${locale.languageCode}_${locale.countryCode}'
          : locale.languageCode;

  return NumberFormat.compact(locale: localeCode).format(value);
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
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsetsDirectional.fromSTEB(16, 16, 16, 12),
                child: _Header(),
              ),
            ),
            _buildFilterBar(context, vm),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8),
                child: FavoritesStatusRow(
                  total: vm.cachedFavorites.length,
                  visible: vm.displayFavorites.length,
                  showSync: vm.hasUnfilteredData ||
                      vm.cachedFavorites.isNotEmpty ||
                      vm.isLoading,
                  isRefreshing: vm.isRefreshing,
                ),
              ),
            ),
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
      return [
        _buildSkeletonSliver(context),
        _buildLoadingInfoSliver(context, localization),
      ];
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

  Widget _buildSkeletonSliver(BuildContext context) {
    return SliverPadding(
      padding: _gridPadding,
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) => SliverGrid(
          gridDelegate:
              _favoritesGridDelegate(context, constraints.crossAxisExtent),
          delegate: SliverChildBuilderDelegate(
            (context, index) => const FavoriteCardSkeleton(),
            childCount: 6,
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: true,
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingInfoSliver(
      BuildContext context, AppLocalizations localization) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return SliverToBoxAdapter(
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

/// The top of the screen, as Search and Home have it: the person's avatar, a
/// greeting with a line under it, and the notification bell.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    // listens: true (default). The tabs are kept alive side by side, so this
    // must subscribe to AuthViewModel like Home and Search do; otherwise a name
    // or photo change would not show here until a full rebuild.
    final authVM = Provider.of<AuthViewModel>(context);
    final localization = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
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
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    '${localization.translate('hiGreeting')} $userName',
                    key: ValueKey(userName),
                    style: textTheme.headlineSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  localization.translate('favoritesOverviewTitle'),
                  style: textTheme.bodyMedium?.copyWith(
                    color: colors.onSurface.withValues(alpha: 0.6),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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

/// What the list is made of, and whether it is up to date, in the pill style of
/// the result count on Search: how many favorites are saved, how many the
/// chosen filter shows and, while there is something to sync, whether it is
/// syncing or synced. The pills wrap onto a second line rather than overflow.
class FavoritesStatusRow extends StatelessWidget {
  const FavoritesStatusRow({
    super.key,
    required this.total,
    required this.visible,
    required this.showSync,
    required this.isRefreshing,
  });

  final int total;
  final int visible;
  final bool showSync;
  final bool isRefreshing;

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _StatPill(
          icon: Icons.layers_rounded,
          label: localization.translate('favoritesTotalCountLabel'),
          value: _formatCount(total, localization),
        ),
        _StatPill(
          icon: Icons.visibility_rounded,
          label: localization.translate('favoritesVisibleCountLabel'),
          value: _formatCount(visible, localization),
        ),
        if (showSync) _SyncPill(isRefreshing: isRefreshing),
      ],
    );
  }
}

/// The pill every status item sits in: Search's result-count chip.
class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.primary.withValues(alpha: 0.15)),
      ),
      child: child,
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return _Pill(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colors.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: textTheme.labelMedium?.copyWith(
                color: colors.onSurface.withValues(alpha: 0.7),
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: Text(
              value,
              key: ValueKey<String>(value),
              style: textTheme.labelLarge?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncPill extends StatelessWidget {
  const _SyncPill({required this.isRefreshing});

  final bool isRefreshing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final localization = AppLocalizations.of(context);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      child: _Pill(
        key: ValueKey<bool>(isRefreshing),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            isRefreshing
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                    ),
                  )
                : Icon(
                    Icons.check_circle_rounded,
                    color: colors.primary,
                    size: 16,
                  ),
            const SizedBox(width: 6),
            Text(
              localization.translate(
                isRefreshing ? 'favoritesSyncingChip' : 'favoritesSyncedChip',
              ),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
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
