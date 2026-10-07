import 'dart:math' as math;

import 'package:broker_wallet/src/views/Widgets/user_screen_header.dart';
import 'package:broker_wallet/src/common/utils/svg_icon.dart';
import 'package:flutter/material.dart' hide SearchBar;
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
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
      child: _RefreshWhenShown(
        child: Consumer<SearchViewModel>(
          builder: (context, vm, _) {
            return SafeArea(
              bottom: false,
              child: CustomScrollView(
                // Dragging the results dismisses the keyboard; the results
                // themselves stay.
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                // bigger cache to make scrolling silky
                scrollCacheExtent: const ScrollCacheExtent.pixels(1400),
                slivers: [
                  // Header. It listens to the profile itself, so a profile
                  // update does not rebuild the results.
                  SliverToBoxAdapter(
                    child: Padding(
                      padding:
                          const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 0),
                      child: UserScreenHeader(
                        subtitle: l.translate('searchHeaderSubtitle'),
                      ),
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
                        onSubmitted: vm.submitQuery,
                        animatedHints: _getSearchHints(l),
                      ),
                    ),
                  ),
                  // Filters. Pinned, so they stay reachable, but nothing is
                  // drawn behind them: no panel, no shadow, no tint. The bar is
                  // the page's own colour, so the chips float on the page and
                  // the results simply scroll away under them.
                  SliverAppBar(
                    pinned: true,
                    automaticallyImplyLeading: false,
                    elevation: 0,
                    scrolledUnderElevation: 0,
                    shadowColor: Colors.transparent,
                    surfaceTintColor: Colors.transparent,
                    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                    toolbarHeight: FilterChips.rowHeightOf(context),
                    flexibleSpace: Align(
                      alignment: Alignment.center,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: 16,
                        ),
                        child: FilterChips(
                          filters: vm.filters,
                          onToggle: vm.toggleFilter,
                        ),
                      ),
                    ),
                  ),

                  // Content area
                  ..._contentSlivers(context, vm, l),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _contentSlivers(
    BuildContext context,
    SearchViewModel vm,
    AppLocalizations l,
  ) {
    if (vm.isLoading) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }

    final errorKind = vm.errorKind;
    if (errorKind != null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _ErrorState(
            message: _errorMessage(l, errorKind),
            onRetry: vm.retry,
            l: l,
          ),
        ),
      ];
    }

    // Nothing to answer yet, or a search asked but not answered yet: the
    // starting state, never "no results" for a question that has not been
    // answered.
    if (!vm.hasQuery || !vm.hasAnswer) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            asset: SvgIcon.search,
            title: l.translate('nothingToSeeHere'),
            subtitle: l.translate('trySearchingElse'),
          ),
        ),
      ];
    }

    if (!vm.hasResults) {
      final filter = vm.selectedFilter;
      final filtered = filter != null && filter.labelKey != 'all';
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _NoResults(
            l: l,
            // A filter that hides everything can be cleared from here, without
            // hunting for its chip.
            onClearFilter: filtered
                ? () => vm.toggleFilter(vm.filters.indexOf(filter))
                : null,
          ),
        ),
      ];
    }

    final results = vm.searchResults;
    return [
      // Results label row. It names the query the results answer, which is not
      // always the text in the field while a newer search is pending.
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${l.translate('resultsFor')} “${vm.resultsQuery}”',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _CountChip(count: results.length),
            ],
          ),
        ),
      ),
      // Grid
      SliverPadding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 96),
        sliver: SliverLayoutBuilder(
          builder: (context, constraints) {
            final cardWidth =
                (constraints.crossAxisExtent - _gridSpacing) / _columns;
            // The shape stays 3 : 4 unless the text needs more room.
            final extent = math.max(
              cardWidth / _cardAspectRatio,
              SearchResultCard.minHeightForText(context),
            );
            // Cards keep their state when results change order or a filter is
            // applied, instead of being rebuilt from nothing.
            final indexByKey = <String, int>{
              for (var i = 0; i < results.length; i++) results[i].stableKey: i,
            };
            return SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final result = results[index];
                  return SearchResultCard(
                    key: ValueKey<String>(result.stableKey),
                    result: result,
                    onTap: () => _navigateToDetails(context, result),
                  );
                },
                childCount: results.length,
                findChildIndexCallback: (key) =>
                    key is ValueKey<String> ? indexByKey[key.value] : null,
              ),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _columns,
                crossAxisSpacing: _gridSpacing,
                mainAxisSpacing: _gridSpacing,
                mainAxisExtent: extent,
              ),
            );
          },
        ),
      ),
    ];
  }

  static const int _columns = 2;
  static const double _gridSpacing = 12;
  static const double _cardAspectRatio = 0.75;

  /// What to tell the person about a failed search. The technical error is
  /// never shown.
  static String _errorMessage(AppLocalizations l, SearchErrorKind kind) {
    switch (kind) {
      case SearchErrorKind.network:
        return l.translate('authNetworkFailed');
      case SearchErrorKind.session:
        return l.translate('userSessionExpired');
      case SearchErrorKind.generic:
        return l.translate('errorOccurred');
    }
  }

  void _navigateToDetails(BuildContext context, SearchResult result) {
    // Leave the keyboard down when coming back from the details.
    FocusManager.instance.primaryFocus?.unfocus();
    switch (result.type) {
      case SearchResultType.request:
        context.push('/requested-details', extra: result.data);
        break;
      case SearchResultType.offer:
        final offerId = result.id.trim();
        if (offerId.isNotEmpty) {
          context.push(
            '/offers-details-by-id/${Uri.encodeComponent(offerId)}',
            extra: result.data,
          );
        }
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

/// Asks the view-model to refresh when the Search tab comes back to the front.
///
/// Search is kept alive in the bottom-nav stack, so its records can have changed
/// while it was out of sight; going back to a result that was deleted meanwhile
/// would open a record that is gone. The tab being shown again is told by its
/// [TickerMode], which is off while another tab is in front.
class _RefreshWhenShown extends StatefulWidget {
  final Widget child;
  const _RefreshWhenShown({required this.child});

  @override
  State<_RefreshWhenShown> createState() => _RefreshWhenShownState();
}

class _RefreshWhenShownState extends State<_RefreshWhenShown> {
  bool? _shown;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shown = TickerMode.valuesOf(context).enabled;
    final wasHidden = _shown == false;
    _shown = shown;
    if (wasHidden && shown) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<SearchViewModel>().refreshIfStale();
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
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

class _NoResults extends StatelessWidget {
  final AppLocalizations l;

  /// Set when a filter is hiding results: clears it.
  final VoidCallback? onClearFilter;
  const _NoResults({required this.l, this.onClearFilter});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          EmptyState(
            asset: 'assets/icons/search.svg',
            title: l.translate('noResults'),
            subtitle: l.translate('tryDifferentKeywords'),
          ),
          if (onClearFilter != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: onClearFilter,
              child: Text(l.translate('clearFilter')),
            ),
          ],
        ],
      ),
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
