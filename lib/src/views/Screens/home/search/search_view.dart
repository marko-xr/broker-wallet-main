import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:broker_wallet/src/common/utils/svg_icon.dart';
import 'package:broker_wallet/src/common/utils/images.dart';
import 'package:flutter/material.dart' hide SearchBar;
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:broker_wallet/src/Views/Widgets/notification_icon.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import '../../../../viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:broker_wallet/src/Views/Screens/home/search/widgets/search_bar.dart';
import 'package:broker_wallet/src/Views/Screens/home/search/widgets/search_filter_chips.dart';
import 'package:broker_wallet/src/Views/Widgets/empty_state.dart';
import 'package:broker_wallet/src/Views/Screens/home/search/search_viewmodel.dart';
import 'widgets/search_result_card.dart';

class SearchView extends StatelessWidget {
  const SearchView({super.key});

  // Localized rotating hint suggestions
  List<String> _getSearchHints(AppLocalizations l) => [
        l.translate('searchHintPhoneNumbers'),
        l.translate('searchHintPeople'),
        l.translate('searchHintRequestsOffers'),
        l.translate('searchHintNameProperty'),
        l.translate('searchHintLocation'),
        l.translate('searchHintOffices'),
      ];

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return ChangeNotifierProvider(
      create: (_) => SearchViewModel(),
      child: Consumer<SearchViewModel>(
        builder: (context, vm, _) {
          // listen: true (default) — Search is kept alive in the bottom-nav
          // IndexedStack, so it must subscribe to AuthViewModel like
          // Home/Favorites already do; a one-time listen:false read here was
          // why Search kept showing the old name/image until a full
          // rebuild (e.g. logout/login) instead of updating immediately
          // after a profile save.
          final authVM = Provider.of<AuthViewModel>(context);
          final colorScheme = Theme.of(context).colorScheme;

          return SafeArea(
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) => false,
              child: CustomScrollView(
                // bigger cache to make scrolling silky
                scrollCacheExtent: 1400,
                slivers: [
                  // Header
                  SliverToBoxAdapter(
                    child: Padding(
                      padding:
                          const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 0),
                      child: _Header(localizations: l, authVM: authVM),
                    ),
                  ),
                  // Search bar
                  SliverToBoxAdapter(
                    child: Padding(
                      padding:
                          const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 12),
                      child: SearchBar(
                        hint: l.translate('searchHint'),
                        onChanged: vm.updateQuery,
                        animatedHints: _getSearchHints(l),
                      ),
                    ),
                  ),
                  // Filters (with subtle sticky/elevated look)
                  SliverAppBar(
                    elevation: 0,
                    pinned: true,
                    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                    automaticallyImplyLeading: false,
                    toolbarHeight: 60,
                    flexibleSpace: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.shadow.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Align(
                        alignment: Alignment.center,
                        child: Padding(
                          padding: const EdgeInsetsDirectional.fromSTEB(
                              16, 8, 16, 8),
                          child: FilterChips(
                            filters: vm.filters,
                            onToggle: vm.toggleFilter,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Content area
                  if (vm.isLoading)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (vm.error != null)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _ErrorState(
                        message: vm.error!,
                        onRetry: () => vm.updateQuery(vm.query),
                        l: l,
                      ),
                    )
                  else if (!vm.hasQuery)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyState(
                        asset: SvgIcon.search,
                        title: l.translate('nothingToSeeHere'),
                        subtitle: l.translate('trySearchingElse'),
                      ),
                    )
                  else if (!vm.hasResults)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyState(
                        asset: 'assets/icons/search.svg',
                        title: l.translate('noResults'),
                        subtitle: l.translate('tryDifferentKeywords'),
                      ),
                    )
                  else ...[
                    // Results label row
                    SliverToBoxAdapter(
                      child: Padding(
                        padding:
                            const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${l.translate('resultsFor')} “${vm.query}”',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _CountChip(count: vm.searchResults.length),
                          ],
                        ),
                      ),
                    ),
                    // Grid
                    SliverPadding(
                      padding:
                          const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 20),
                      sliver: SliverGrid(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final result = vm.searchResults[index];
                            return RepaintBoundary(
                              child: SearchResultCard(
                                key: ValueKey('${result.type}_${result.id}'),
                                result: result,
                                onTap: () =>
                                    _navigateToDetails(context, result),
                              ),
                            );
                          },
                          childCount: vm.searchResults.length,
                        ),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.75,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _navigateToDetails(BuildContext context, SearchResult result) {
    switch (result.type) {
      case SearchResultType.request:
        context.push('/requested-details', extra: result.data);
        break;
      case SearchResultType.offer:
        context.push('/offers-details', extra: result.data);
        break;
      case SearchResultType.owner:
        context.push('/owners-details', extra: result.data);
        break;
      case SearchResultType.office:
        context.push('/offices-details', extra: result.data);
        break;
      case SearchResultType.watchmen:
        context.push('/watchmen-details', extra: result.data);
        break;
      case SearchResultType.broker:
        context.push('/brokers-details', extra: result.data);
        break;
    }
  }
}

class _Header extends StatelessWidget {
  final AppLocalizations localizations;
  final AuthViewModel authVM;
  const _Header({required this.localizations, required this.authVM});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final resolvedName = authVM.displayName.trim();
    final userName = resolvedName.isNotEmpty
        ? resolvedName
        : localizations.translate('favoritesGuestUser');
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        GestureDetector(
          onTap: () => context.push('/edit-profile'),
          child: ClipOval(
            child: SizedBox(
              width: 48,
              height: 48,
              child: authVM.currentUser?.profileImageUrl != null &&
                      authVM.currentUser!.profileImageUrl!.isNotEmpty
                  ? OfflineMediaService.instance.buildOfflineAwareImage(
                      imageUrl: authVM.currentUser!.profileImageUrl!,
                      fit: BoxFit.cover,
                      width: 48,
                      height: 48,
                    )
                  : Image.asset(
                      AppImages.avatarPlaceholder,
                      fit: BoxFit.cover,
                      width: 48,
                      height: 48,
                    ),
            ),
          ),
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
                    '${localizations.translate('hiGreeting')} $userName',
                    key: ValueKey(userName),
                    style: t.headlineSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  localizations.translate('welcomeMessage'),
                  style: t.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
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

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final AppLocalizations l;
  const _ErrorState(
      {required this.message, required this.onRetry, required this.l});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.error_outline, size: 64, color: cs.error),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: onRetry,
          child: Text(l.translate('tryAgain')),
        ),
      ],
    );
  }
}

class _CountChip extends StatelessWidget {
  final int count;
  const _CountChip({required this.count});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.primary.withValues(alpha: 0.15)),
      ),
      child: Text(
        '$count',
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(color: cs.primary, fontWeight: FontWeight.w700),
      ),
    );
  }
}
