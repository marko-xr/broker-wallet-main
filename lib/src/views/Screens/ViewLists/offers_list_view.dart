import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:go_router/go_router.dart';
import 'package:broker_wallet/src/Views/Widgets/back_arrow_button.dart';
import 'package:broker_wallet/src/Views/Widgets/property_status_indicator.dart';
import 'package:provider/provider.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:intl/intl.dart';
import '../../../data/models/ScreensModel/offers_model.dart';
import '../../../viewmodels/ListScreens/list_offers_viewmodel.dart';
import '../../../data/models/property_status.dart';

class OffersListView extends StatefulWidget {
  const OffersListView({super.key});

  @override
  State<OffersListView> createState() => _OffersListViewState();
}

class _OffersListViewState extends State<OffersListView> {
  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;

    return ChangeNotifierProvider(
      create: (_) => OffersListViewModel(),
      child: Consumer<OffersListViewModel>(
        builder: (context, vm, _) {
          return Scaffold(
            backgroundColor: colors.surface,
            resizeToAvoidBottomInset: false,
            appBar: AppBar(
              leading: const BackArrowButton(),
              title: Text(
                loc.translate(
                    vm.showInactiveOnly ? 'archivedOffers' : 'offers'),
                style: texts.titleLarge,
              ),
              centerTitle: true,
              elevation: 0,
              backgroundColor: colors.surface,
              actions: [
                IconButton(
                  icon: Icon(
                    vm.showInactiveOnly
                        ? Icons.archive_outlined
                        : Icons.archive,
                    color:
                        vm.showInactiveOnly ? colors.primary : colors.onSurface,
                  ),
                  onPressed: vm.toggleStatusFilter,
                  tooltip: loc.translate(vm.showInactiveOnly
                      ? 'showActiveOffers'
                      : 'showArchivedOffers'),
                ),
              ],
            ),
            floatingActionButton: FloatingActionButton(
              onPressed: () => context.push('/add-offers'),
              backgroundColor: colors.primary,
              shape: const CircleBorder(),
              child: const Icon(Icons.add, color: Colors.white),
            ),
            body: StreamBuilder<List<OfferModel>>(
              stream: vm.offersStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _buildShimmerLoading();
                }

                if (snapshot.hasError) {
                  return _buildErrorWidget(
                    vm,
                    colors,
                    texts,
                    loc,
                    snapshot.error.toString(),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return _buildEmptyWidget(colors, texts, loc);
                }

                vm.offers = snapshot.data!;

                return _buildOffersListWithDateSeparators(
                  vm.filteredOffers,
                  vm,
                  loc,
                  colors,
                  texts,
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildOffersListWithDateSeparators(
    List<OfferModel> offers,
    OffersListViewModel vm,
    AppLocalizations loc,
    ColorScheme colors,
    TextTheme texts,
  ) {
    // Group offers by week
    final groupedOffers = _groupOffersByWeek(offers);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // Statistics Cards
        if (vm.offers.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _buildStatisticsCards(vm.offers, vm, colors, texts, loc),
            ),
          ),

        // Show empty state when filter is applied but no results
        if (offers.isEmpty && vm.selectedFilter != null)
          SliverToBoxAdapter(
            child: _buildFilteredEmptyState(vm, colors, texts, loc),
          ),

        // Grouped Offers List
        ...groupedOffers.entries.map((entry) {
          final weekKey = entry.key;
          final weekOffers = entry.value;

          return SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index == 0) {
                  // First item is the date separator
                  return _buildDateSeparator(weekKey, colors, texts, loc);
                }

                // Adjust index for offer items
                final offerIndex = index - 1;
                final offer = weekOffers[offerIndex];

                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: _EnhancedOfferTile(
                    key: ValueKey('offer_${offer.id ?? offerIndex}'),
                    offer: offer,
                    onDelete: () =>
                        _showDeleteConfirmation(offer, vm, loc, colors),
                    onEdit: () {
                      // Navigate to edit if needed
                    },
                    loc: loc,
                    viewModel: vm,
                    index: offerIndex,
                  ),
                );
              },
              childCount: weekOffers.length + 1, // +1 for date separator
            ),
          );
        }),

        // Bottom spacing
        const SliverToBoxAdapter(
          child: SizedBox(height: 80),
        ),
      ],
    );
  }

  Widget _buildShimmerLoading() {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: List.generate(
            5,
            (index) => Container(
              margin: const EdgeInsets.only(bottom: 16),
              child: const _ShimmerContainer(
                height: 120,
                width: double.infinity,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorWidget(
    OffersListViewModel vm,
    ColorScheme colors,
    TextTheme texts,
    AppLocalizations loc, [
    String? errorMessage,
  ]) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colors.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.wifi_off_rounded,
                size: 48,
                color: colors.error,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              loc.translate('errorLoading'),
              style: texts.headlineSmall?.copyWith(
                color: colors.error,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                errorMessage ?? vm.error ?? loc.translate('errorLoading'),
                style: texts.bodyMedium?.copyWith(
                  color: colors.onSurface.withValues(alpha: 0.7),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyWidget(
    ColorScheme colors,
    TextTheme texts,
    AppLocalizations loc,
  ) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colors.primary.withValues(alpha: 0.1),
                    colors.secondary.withValues(alpha: 0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: SvgPicture.asset(
                'assets/icons/offers-svg.svg',
                width: 64,
                height: 64,
                colorFilter: ColorFilter.mode(
                  colors.primary,
                  BlendMode.srcIn,
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              loc.translate('noOffersYet'),
              style: texts.headlineSmall?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                loc.translate('addFirstOffer'),
                style: texts.bodyLarge?.copyWith(
                  color: colors.onSurface.withValues(alpha: 0.6),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, List<OfferModel>> _groupOffersByWeek(List<OfferModel> offers) {
    final Map<String, List<OfferModel>> grouped = {};

    // Sort offers by creation date (newest first)
    final sortedOffers = List<OfferModel>.from(offers);
    sortedOffers.sort((a, b) {
      final dateA = a.createdAt;
      final dateB = b.createdAt;
      return dateB.compareTo(dateA); // Newest first
    });

    for (final offer in sortedOffers) {
      final date = offer.createdAt;
      final weekKey = _getWeekKey(date);

      if (!grouped.containsKey(weekKey)) {
        grouped[weekKey] = [];
      }
      grouped[weekKey]!.add(offer);
    }

    return grouped;
  }

  String _getWeekKey(DateTime date) {
    // Get the start of the week (Monday)
    final weekStart = date.subtract(Duration(days: date.weekday - 1));

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(date.year, date.month, date.day);

    // Check if it's this week
    final thisWeekStart = today.subtract(Duration(days: today.weekday - 1));
    final thisWeekEnd = thisWeekStart.add(const Duration(days: 6));

    if (dateOnly.isAfter(thisWeekStart.subtract(const Duration(days: 1))) &&
        dateOnly.isBefore(thisWeekEnd.add(const Duration(days: 1)))) {
      return 'this_week';
    }

    // Check if it's last week
    final lastWeekStart = thisWeekStart.subtract(const Duration(days: 7));
    final lastWeekEnd = lastWeekStart.add(const Duration(days: 6));

    if (dateOnly.isAfter(lastWeekStart.subtract(const Duration(days: 1))) &&
        dateOnly.isBefore(lastWeekEnd.add(const Duration(days: 1)))) {
      return 'last_week';
    }

    // For other weeks, use the week start date
    return '${weekStart.year}-${weekStart.month}-${weekStart.day}';
  }

  Widget _buildDateSeparator(String weekKey, ColorScheme colors,
      TextTheme texts, AppLocalizations loc) {
    String displayText;
    Color accentColor;

    if (weekKey == 'this_week') {
      displayText = loc.translate('thisWeek');
      accentColor = colors.primary;
    } else if (weekKey == 'last_week') {
      displayText = loc.translate('lastWeek');
      accentColor = colors.secondary;
    } else {
      // Parse the date from weekKey
      final parts = weekKey.split('-');
      final date = DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );

      // Format: "September 2, Monday"
      final localeCode = loc.locale.toString();
      final dayFormatter = DateFormat('EEEE', localeCode);
      final monthFormatter = DateFormat('MMMM d', localeCode);
      final separator = loc.locale.languageCode == 'ar' ? '، ' : ', ';

      displayText =
          '${monthFormatter.format(date)}$separator${dayFormatter.format(date)}';
      accentColor = colors.tertiary;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      child: Row(
        children: [
          // Left line
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    accentColor.withValues(alpha: 0.3),
                  ],
                  begin: AlignmentDirectional.centerStart,
                  end: AlignmentDirectional.centerEnd,
                ),
              ),
            ),
          ),

          // Date text
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              displayText,
              style: texts.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: accentColor,
                letterSpacing: 0.5,
              ),
            ),
          ),

          // Right line
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    accentColor.withValues(alpha: 0.3),
                    Colors.transparent,
                  ],
                  begin: AlignmentDirectional.centerStart,
                  end: AlignmentDirectional.centerEnd,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDeleteConfirmation(
    OfferModel offer,
    OffersListViewModel vm,
    AppLocalizations loc,
    ColorScheme colors,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFC81E1E),
                size: 28,
              ),
              const SizedBox(width: 12),
              Text(
                loc.translate('deleteOffer'),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                loc.translate('confirmDeleteOffer'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onSurface.withValues(alpha: 0.8),
                    ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE6E6),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFFFFCCCC),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.business_rounded,
                      size: 18,
                      color: Color(0xFFC81E1E),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        offer.offerType == 'rent'
                            ? loc.translate('rentOffer')
                            : loc.translate('saleOffer'),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFFC81E1E),
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.surface,
                      foregroundColor: colors.onSurface,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: colors.outline.withValues(alpha: 0.3),
                          width: 1.5,
                        ),
                      ),
                      elevation: 0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: colors.onSurface.withValues(alpha: 0.7),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          loc.translate('cancel'),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: colors.onSurface.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFC81E1E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                      shadowColor:
                          const Color(0xFFC81E1E).withValues(alpha: 0.4),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.delete_rounded,
                            size: 18, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          'Delete',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      if (offer.id != null) {
        await vm.deleteOffer(offer.id!, context);
      }
    }
  }

  Widget _buildFilteredEmptyState(
    OffersListViewModel vm,
    ColorScheme colors,
    TextTheme texts,
    AppLocalizations loc,
  ) {
    final titleKey =
        vm.showInactiveOnly ? 'noArchivedOffersYet' : 'noOffersYet';
    final noFoundMessage = loc.translate(vm.selectedFilter == 'rent'
        ? (vm.showInactiveOnly
            ? 'noArchivedRentOffersFound'
            : 'noRentOffersFound')
        : (vm.showInactiveOnly
            ? 'noArchivedSellOffersFound'
            : 'noSellOffersFound'));

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.4,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                vm.selectedFilter == 'rent'
                    ? Icons.home_outlined
                    : Icons.sell_outlined,
                size: 48,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              loc.translate(titleKey),
              style: texts.titleLarge?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              noFoundMessage,
              style: texts.bodyMedium?.copyWith(
                color: colors.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => vm.clearFilter(),
              child: Text(
                loc.translate('allOffers'),
                style: TextStyle(
                  color: colors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatisticsCards(
    List<OfferModel> offers,
    OffersListViewModel vm,
    ColorScheme colors,
    TextTheme texts,
    AppLocalizations loc,
  ) {
    final relevantOffers = (vm.showInactiveOnly
            ? offers.where((o) => o.status.isInactive)
            : offers.where((o) => o.status.isActive))
        .toList();
    final rentCount = relevantOffers.where((o) => o.offerType == 'rent').length;
    final sellCount = relevantOffers.where((o) => o.offerType == 'sell').length;

    return Row(
      children: [
        Expanded(
          child: _StatCard(
            title: loc.translate('rentOffers'),
            count: rentCount,
            icon: Icons.home_outlined,
            color: colors.primary,
            gradient: [colors.primary.withValues(alpha: 0.8), colors.primary],
            isSelected: vm.selectedFilter == 'rent',
            onTap: () => vm.toggleFilter('rent'),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _StatCard(
            title: loc.translate('saleOffers'),
            count: sellCount,
            icon: Icons.sell_outlined,
            color: colors.secondary,
            gradient: [
              colors.secondary.withValues(alpha: 0.8),
              colors.secondary
            ],
            isSelected: vm.selectedFilter == 'sell',
            onTap: () => vm.toggleFilter('sell'),
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final int count;
  final IconData icon;
  final Color color;
  final List<Color> gradient;
  final bool isSelected;
  final VoidCallback onTap;

  const _StatCard({
    required this.title,
    required this.count,
    required this.icon,
    required this.color,
    required this.gradient,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final texts = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors:
                  isSelected ? [color, color.withValues(alpha: 0.9)] : gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: isSelected ? 0.4 : 0.3),
                blurRadius: isSelected ? 16 : 12,
                offset: const Offset(0, 6),
              ),
            ],
            border: isSelected
                ? Border.all(
                    color: Colors.white.withValues(alpha: 0.3), width: 2)
                : null,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: isSelected ? 0.3 : 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: isSelected ? 22 : 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 22.0),
                      child: Text(
                        count.toString(),
                        style: texts.headlineMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 24,
                            ) ??
                            const TextStyle(color: Colors.white),
                      ),
                    ),
                    Text(
                      title,
                      style: texts.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                          ) ??
                          const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EnhancedOfferTile extends StatelessWidget {
  final OfferModel offer;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final AppLocalizations loc;
  final OffersListViewModel viewModel;
  final int index;

  const _EnhancedOfferTile({
    super.key,
    required this.offer,
    required this.onDelete,
    required this.onEdit,
    required this.loc,
    required this.viewModel,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;
    final isRent = offer.offerType == 'rent';
    final squareFootageValue = offer.squareFootage.trim();

    return Dismissible(
      key: Key('offer_${offer.id ?? index}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        onDelete();
        return false;
      },
      background: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFC72828),
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsetsDirectional.only(
          end: 20,
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete_outline, color: Colors.white, size: 28),
            SizedBox(height: 4),
            Text(
              'Delete',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colors.surface.withValues(alpha: 0.6),
              colors.surface.withValues(alpha: 0.4),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: colors.tertiary.withValues(alpha: 0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
              spreadRadius: 0,
            ),
          ],
          border: Border.all(
            color: colors.tertiary.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            overlayColor: WidgetStateProperty.all<Color>(Colors.transparent),
            onTap: () {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) {
                  context.push('/offers-details', extra: offer);
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Avatar
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.primary.withValues(alpha: 0.1),
                        ),
                        child: ClipOval(
                          child: SvgPicture.asset(
                            'assets/icons/Offers-Avatar.svg',
                            fit: BoxFit.cover,
                            width: 50,
                            height: 50,
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),

                      // Content
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Property Type with icon
                            Row(
                              children: [
                                Icon(
                                  _getPropertyIcon(offer.propertyType),
                                  size: 18,
                                  color: Colors.black,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    _getPropertyTypeDisplay(offer),
                                    style: texts.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: colors.onSurface,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _getFormattedDate(offer.createdAt),
                                  style: texts.bodySmall?.copyWith(
                                    color:
                                        colors.onSurface.withValues(alpha: 0.7),
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),

                            const SizedBox(height: 6),
                            // Location and Specific Property Type
                            Row(
                              children: [
                                Icon(
                                  Icons.home_rounded,
                                  size: 16,
                                  color:
                                      colors.onSurface.withValues(alpha: 0.8),
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    _getSpecificPropertyTypeDisplay(offer),
                                    style: texts.bodySmall?.copyWith(
                                      color: colors.onSurface
                                          .withValues(alpha: 0.8),
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 40),
                                Icon(
                                  Icons.location_on_rounded,
                                  size: 16,
                                  color:
                                      colors.onSurface.withValues(alpha: 0.6),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    _getCityDisplayName(offer.selectedCity),
                                    style: texts.bodyMedium?.copyWith(
                                      color: colors.onSurface
                                          .withValues(alpha: 0.8),
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Badges row: type + status + square footage
                            Wrap(
                              spacing: 4,
                              runSpacing: 8,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: isRent
                                          ? [
                                              colors.primary,
                                              colors.primary
                                                  .withValues(alpha: 0.8)
                                            ]
                                          : [
                                              colors.secondary,
                                              colors.secondary
                                                  .withValues(alpha: 0.8)
                                            ],
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: isRent
                                            ? colors.primary
                                                .withValues(alpha: 0.3)
                                            : colors.secondary
                                                .withValues(alpha: 0.3),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isRent
                                            ? Icons.home_rounded
                                            : Icons.sell_rounded,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        offer.offerType == 'rent'
                                            ? loc.translate('rent')
                                            : loc.translate('sale'),
                                        style: texts.labelSmall?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Status indicator
                                PropertyStatusChip(
                                  status: offer.status,
                                  onTap: () => _showStatusSelector(context),
                                ),

                                if (squareFootageValue.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: colors.primary
                                          .withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: colors.primary
                                            .withValues(alpha: 0.2),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.square_foot,
                                          size: 14,
                                          color: colors.primary,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${squareFootageValue} ${loc.translate('squareFootageUnit')}',
                                          style: texts.labelSmall?.copyWith(
                                            color: colors.primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (offer.minPrice.isNotEmpty ||
                                offer.maxPrice.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.tertiary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color:
                                        colors.tertiary.withValues(alpha: 0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.payments_rounded,
                                      size: 12,
                                      color: colors.tertiary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _getPriceRange(offer),
                                      style: texts.labelSmall?.copyWith(
                                        color: colors.tertiary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _getCityDisplayName(String city) {
    if (city.isEmpty) return loc.translate('noCitySelected');

    // Try to get localized city name
    String cityKey = _cityLocalizationKey(city);
    String localized = loc.translate(cityKey);

    // If translation returns the key itself (not found), return original
    if (localized == '** $cityKey not found') {
      return city;
    }
    return localized;
  }

  String _cityLocalizationKey(String city) {
    switch (city.toLowerCase().replaceAll(' ', '')) {
      case "dubai":
        return 'dubai';
      case "abudhabi":
        return 'abuDhabi';
      case "khorfakkan":
        return 'khorFakkan';
      case "alain":
        return 'alAin';
      case "rasalkhaimah":
        return 'rasAlKhaimah';
      case "fujairah":
        return 'fujairah';
      case "sharjah":
        return 'sharjah';
      case "ajman":
        return 'ajman';
      case "ummalquwain":
        return 'ummAlQuwain';
      default:
        return city; // fallback
    }
  }

  String _getFormattedDate(DateTime date) {
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }

  String _getPropertyTypeDisplay(OfferModel offer) {
    final propertyTypeRaw = (offer.propertyType ?? '').trim();

    if (propertyTypeRaw.isEmpty) {
      return loc.translate('propertyTypeNotSpecified');
    }

    switch (propertyTypeRaw.toLowerCase()) {
      case 'residential':
        return loc.translate('residential');
      case 'commercial':
        return loc.translate('commercial');
      case 'furnished':
        return loc.translate('furnished');
      default:
        return propertyTypeRaw;
    }
  }

  String _getSpecificPropertyTypeDisplay(OfferModel offer) {
    final specificTypeRaw = offer.specificPropertyType.trim();

    if (specificTypeRaw.isEmpty) {
      return loc.translate('propertyTypeNotSpecified');
    }

    return _getLocalizedSpecificType(specificTypeRaw);
  }

  String _getLocalizedSpecificType(String specificType) {
    // Convert spaces to camelCase for lookup in localization files
    String key = _propertySubTypeKey(specificType);
    String localized = loc.translate(key);

    // If translation returns the key itself (not found), return original
    if (localized == '** $key not found') {
      return specificType;
    }
    return localized;
  }

  String _propertySubTypeKey(String type) {
    // camel/snake/label mapping to arb keys
    switch (type.toLowerCase().replaceAll(' ', '').replaceAll('&', 'and')) {
      case "apartment":
        return "apartment";
      case "villa":
        return "villa";
      case "studio":
        return "studio";
      case "townhouse":
        return "townhouse";
      case "penthouse":
        return "penthouse";
      case "compound":
        return "compound";
      case "duplex":
        return "duplex";
      case "fullfloor":
        return "fullFloor";
      case "halffloor":
        return "halfFloor";
      case "wholebuilding":
        return "wholeBuilding";
      case "land":
        return "land";
      case "bulkrentunit":
        return "bulkRentUnit";
      case "bungalow":
        return "bungalow";
      case "hotelandhotelapartment":
      case "hotelhotelapartment":
        return "hotelAndHotelApartment";
      case "officespace":
        return "officeSpace";
      case "retail":
        return "retail";
      case "warehouse":
        return "warehouse";
      case "shop":
        return "shop";
      case "showroom":
        return "showRoom";
      case "bulksaleunit":
        return "bulkSaleUnit";
      case "factory":
        return "factory";
      case "laborcamp":
        return "laborCamp";
      case "staffaccommodation":
        return "staffAccommodation";
      case "businesscentre":
        return "businessCentre";
      case "farm":
        return "farm";
      case "offices":
        return "offices"; // fallback for 'Offices'
      default:
        return type;
    }
  }

  String _getPriceRange(OfferModel offer) {
    if (offer.minPrice.isNotEmpty && offer.maxPrice.isNotEmpty) {
      return '${offer.minPrice} - ${offer.maxPrice} AED';
    } else if (offer.minPrice.isNotEmpty) {
      return '${loc.translate('from')} ${offer.minPrice} AED';
    } else if (offer.maxPrice.isNotEmpty) {
      return '${loc.translate('upTo')} ${offer.maxPrice} AED';
    }
    return loc.translate('priceOnRequest');
  }

  IconData _getPropertyIcon(String? propertyType) {
    switch (propertyType?.toLowerCase()) {
      case 'residential':
        return Icons.home_rounded;
      case 'commercial':
        return Icons.business_rounded;
      case 'furnished':
        return Icons.chair_rounded;
      default:
        return Icons.location_city_rounded;
    }
  }

  void _showStatusSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => PropertyStatusSelector(
        currentStatus: offer.status,
        allowedStatuses: PropertyStatus.offerStatuses,
        onStatusSelected: (newStatus) {
          if (offer.id != null) {
            viewModel.updateOfferStatus(offer.id!, newStatus);
          }
        },
      ),
    );
  }
}

// --- Simple shimmer used in both screens ---
class _ShimmerContainer extends StatefulWidget {
  final double height;
  final double width;

  const _ShimmerContainer({
    required this.height,
    required this.width,
  });

  @override
  State<_ShimmerContainer> createState() => _ShimmerContainerState();
}

class _ShimmerContainerState extends State<_ShimmerContainer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();
    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: [
                colors.surface.withValues(alpha: 0.4),
                colors.surface.withValues(alpha: 0.8),
                colors.surface.withValues(alpha: 0.4),
              ],
              stops: const [0.0, 0.5, 1.0],
              begin: Alignment(-1.0 + _animation.value, 0.0),
              end: Alignment(1.0 + _animation.value, 0.0),
            ),
          ),
        );
      },
    );
  }
}
