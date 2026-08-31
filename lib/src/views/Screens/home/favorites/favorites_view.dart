import 'package:broker_wallet/src/Views/Widgets/empty_state.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/utils/images.dart';
import 'package:broker_wallet/src/common/utils/svg_icon.dart';
import '../../../../viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:broker_wallet/src/Views/Screens/home/favorites/favorites_viewmodel.dart';
import 'package:broker_wallet/src/Views/Screens/home/favorites/favorites_filter_chips.dart';
import 'package:broker_wallet/src/Views/Widgets/notification_icon.dart';
import 'package:broker_wallet/src/Views/Screens/home/favorites/favorites_card.dart';
import 'package:broker_wallet/src/Views/Screens/home/favorites/favorites_item_model.dart';
import 'package:broker_wallet/src/Views/Screens/home/search/widgets/image_cache_manager.dart';
import 'package:broker_wallet/src/services/optimistic_favorites_service.dart';
import 'package:intl/intl.dart';

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
          final authVM = Provider.of<AuthViewModel>(context);

          vm.updateLocalization(localization);

          final slivers = <Widget>[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
              sliver: SliverToBoxAdapter(
                child: _buildHeaderCard(context, localization, authVM, vm),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              sliver: SliverToBoxAdapter(
                child: _buildFilterBackdrop(context, vm),
              ),
            ),
          ];

          final syncStatus = _buildSyncStatusChip(context, vm, localization);
          if (syncStatus != null) {
            slivers.add(
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                sliver: SliverToBoxAdapter(child: syncStatus),
              ),
            );
          }

          slivers.addAll(_buildBodySlivers(context, vm, localization));

          return SafeArea(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context)
                        .colorScheme
                        .surface
                        .withValues(alpha: 0.8),
                    Theme.of(context).scaffoldBackgroundColor,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: RefreshIndicator(
                onRefresh: vm.refresh,
                edgeOffset: 24,
                displacement: 120,
                color: Theme.of(context).colorScheme.primary,
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  cacheExtent: 1200,
                  slivers: slivers,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterBackdrop(BuildContext context, FavoritesViewModel vm) {
    final colors = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colors.outline.withValues(alpha: 0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: FavoriteFilterChips(
          filters: vm.filters,
          onToggle: vm.toggleFilter,
        ),
      ),
    );
  }

  Widget? _buildSyncStatusChip(BuildContext context, FavoritesViewModel vm,
      AppLocalizations localization) {
    if (!vm.hasUnfilteredData && vm.cachedFavorites.isEmpty && !vm.isLoading) {
      return null;
    }

    final colors = Theme.of(context).colorScheme;

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        child: Container(
          key: ValueKey<bool>(vm.isRefreshing),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              vm.isRefreshing
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(colors.primary),
                      ),
                    )
                  : Icon(
                      Icons.check_circle_rounded,
                      color: colors.primary,
                      size: 18,
                    ),
              const SizedBox(width: 8),
              Text(
                localization.translate(vm.isRefreshing
                    ? 'favoritesSyncingChip'
                    : 'favoritesSyncedChip'),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
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
      const SliverToBoxAdapter(child: SizedBox(height: 48)),
    ];
  }

  Widget _buildSkeletonSliver(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 18,
          crossAxisSpacing: 16,
          childAspectRatio: 0.8,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => const FavoriteCardSkeleton(),
          childCount: 6,
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: true,
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

  Widget _buildErrorSliver(BuildContext context, FavoritesViewModel vm,
      AppLocalizations localization) {
    final colors = Theme.of(context).colorScheme;

    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 64,
              color: colors.error,
            ),
            const SizedBox(height: 18),
            Text(
              localization.translate('favoritesErrorTitle'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
              textAlign: TextAlign.center,
            ),
            if (vm.error != null) ...[
              const SizedBox(height: 8),
              Text(
                vm.error!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onSurface.withValues(alpha: 0.65),
                    ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                vm.refresh();
              },
              child: Text(
                localization.translate('favoritesErrorAction'),
              ),
            ),
          ],
        ),
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
        child: EmptyState(
          asset: SvgIcon.markedFavorite,
          title: '$titlePrefix $filterLabel',
          subtitle: localization.translate('favoritesFilterEmptySubtitle'),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(BuildContext context, AppLocalizations localization,
      AuthViewModel authVM, FavoritesViewModel vm) {
    final colors = Theme.of(context).colorScheme;
    final resolvedName = authVM.displayName.trim();
    final userName = resolvedName.isNotEmpty
        ? resolvedName
        : localization.translate('favoritesGuestUser');
    final greeting = localization.translate('hiGreeting');

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.primary.withValues(alpha: 0.18),
            colors.secondary.withValues(alpha: 0.12),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: colors.primary.withValues(alpha: 0.12),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: 0.15),
            blurRadius: 32,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAvatar(context, authVM),
                const SizedBox(width: 16),
                Expanded(
                  child: GestureDetector(
                    onTap: () => context.push('/edit-profile'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$greeting $userName',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                color: colors.onPrimary,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          localization.translate('favoritesOverviewTitle'),
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                color: colors.onPrimary.withValues(alpha: 0.92),
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
                const NotificationIcon(),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _headerChip(
                    context,
                    icon: Icons.layers_rounded,
                    label: localization.translate('favoritesTotalCountLabel'),
                    value:
                        _formatCount(vm.cachedFavorites.length, localization),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _headerChip(
                    context,
                    icon: Icons.visibility_rounded,
                    label: localization.translate('favoritesVisibleCountLabel'),
                    value:
                        _formatCount(vm.displayFavorites.length, localization),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              localization.translate('favoritesRefreshHint'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onPrimary.withValues(alpha: 0.78),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(BuildContext context, AuthViewModel authVM) {
    final profileImage = authVM.currentUser?.profileImageUrl;

    return GestureDetector(
      onTap: () => context.push('/edit-profile'),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          width: 56,
          height: 56,
          child: profileImage != null && profileImage.isNotEmpty
              ? OfflineMediaService.instance.buildOfflineAwareImage(
                  imageUrl: profileImage,
                  fit: BoxFit.cover,
                  width: 56,
                  height: 56,
                )
              : Image.asset(
                  AppImages.avatarPlaceholder,
                  fit: BoxFit.cover,
                  width: 56,
                  height: 56,
                ),
        ),
      ),
    );
  }

  Widget _headerChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colors.primary.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 18,
            color: colors.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.onSurface.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, animation) =>
                      FadeTransition(opacity: animation, child: child),
                  child: Text(
                    value,
                    key: ValueKey<String>(value),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 18,
          crossAxisSpacing: 16,
          childAspectRatio: 0.8,
        ),
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
