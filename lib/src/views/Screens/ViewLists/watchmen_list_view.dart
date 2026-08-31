import 'package:broker_wallet/src/common/utils/images.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import 'package:broker_wallet/src/Views/Widgets/back_arrow_button.dart';
import 'package:provider/provider.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

import '../../../data/models/ScreensModel/watchmen_model.dart';
import '../../../viewmodels/ListScreens/list_watchmen_viewmodel.dart';

class WatchmenListView extends StatefulWidget {
  const WatchmenListView({super.key});

  @override
  State<WatchmenListView> createState() => _WatchmenListViewState();
}

class _WatchmenListViewState extends State<WatchmenListView> {
  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;

    return ChangeNotifierProvider(
      create: (_) => WatchmenListViewModel(),
      child: Consumer<WatchmenListViewModel>(
        builder: (context, vm, _) {
          return Scaffold(
            backgroundColor: colors.surface,
            resizeToAvoidBottomInset: false,
            appBar: AppBar(
              leading: const BackArrowButton(),
              title: Text(
                loc.translate('watchmen'),
                style: texts.titleLarge,
              ),
              centerTitle: true,
              elevation: 0,
              backgroundColor: colors.surface,
            ),
            floatingActionButton: FloatingActionButton(
              onPressed: () => context.push('/add-watchmen'),
              backgroundColor: colors.primary,
              shape: const CircleBorder(),
              child: const Icon(Icons.add, color: Colors.white),
            ),

            // Content
            body: StreamBuilder<List<WatchmenModel>>(
              stream: vm.watchmenStream,
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

                return _buildWatchmenListWithDateSeparators(
                  snapshot.data!,
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
              child: _ShimmerContainer(
                height: 120,
                width: double.infinity,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorWidget(WatchmenListViewModel vm, ColorScheme colors,
      TextTheme texts, AppLocalizations loc,
      [String? errorMessage]) {
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
      ColorScheme colors, TextTheme texts, AppLocalizations loc) {
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
                    colors.tertiary.withValues(alpha: 0.1),
                    colors.primary.withValues(alpha: 0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: SvgPicture.asset(
                'assets/icons/watchman-svg.svg',
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
              loc.translate('noWatchmenYet'),
              style: texts.headlineSmall?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                loc.translate('addFirstWatchmen'),
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

  Widget _buildWatchmenListWithDateSeparators(
    List<WatchmenModel> watchmen,
    WatchmenListViewModel vm,
    AppLocalizations loc,
    ColorScheme colors,
    TextTheme texts,
  ) {
    // Group watchmen by week
    final groupedWatchmen = _groupWatchmenByWeek(watchmen);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // Statistics Card
        if (watchmen.isNotEmpty)
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.all(16),
              child: _buildStatisticsCard(watchmen, colors, texts, loc),
            ),
          ),

        // Generate slivers for each week group
        ...groupedWatchmen.entries.map((entry) {
          final weekKey = entry.key;
          final weekWatchmen = entry.value;

          return SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index == 0) {
                  // First item is always the date separator
                  return _buildDateSeparator(weekKey, colors, texts, loc);
                }

                // Adjust index for the actual watchmen data
                final watchmenIndex = index - 1;
                final w = weekWatchmen[watchmenIndex];

                return Container(
                  margin:
                      const EdgeInsets.only(bottom: 16, left: 16, right: 16),
                  child: _EnhancedWatchmenTile(
                    key: ValueKey('watchmen_${w.id ?? watchmenIndex}'),
                    watchmen: w,
                    onDelete: () => _showDeleteConfirmation(w, vm, loc, colors),
                    onEdit: () {
                      // Navigate to edit if needed
                    },
                    onCall: () => _makePhoneCall(w.phoneNumber),
                    onWhatsApp: () => _openWhatsApp(w.phoneNumber, w.name),
                    loc: loc,
                    index: watchmenIndex,
                  ),
                );
              },
              childCount: weekWatchmen.length + 1, // +1 for date separator
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

  Widget _buildStatisticsCard(List<WatchmenModel> watchmen, ColorScheme colors,
      TextTheme texts, AppLocalizations loc) {
    final totalWatchmen = watchmen.length;
    final watchmenWithNotes = watchmen.where((w) => w.notes.isNotEmpty).length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors.primary.withValues(alpha: 0.8), colors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colors.tertiary.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.security_outlined,
                color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  totalWatchmen.toString(),
                  style: texts.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  loc.translate('totalWatchmen'),
                  style: texts.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Icon(Icons.note_outlined, color: Colors.white, size: 20),
                const SizedBox(height: 4),
                Text(
                  '$watchmenWithNotes',
                  style: texts.bodySmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Map<String, List<WatchmenModel>> _groupWatchmenByWeek(
      List<WatchmenModel> watchmen) {
    final Map<String, List<WatchmenModel>> grouped = {};

    // Sort watchmen by creation date (newest first)
    final sortedWatchmen = List<WatchmenModel>.from(watchmen);
    sortedWatchmen.sort((a, b) {
      final dateA = a.createdAt ?? DateTime.now();
      final dateB = b.createdAt ?? DateTime.now();
      return dateB.compareTo(dateA); // Newest first
    });

    for (final watchman in sortedWatchmen) {
      final date = watchman.createdAt ?? DateTime.now();
      final weekKey = _getWeekKey(date);

      if (!grouped.containsKey(weekKey)) {
        grouped[weekKey] = [];
      }
      grouped[weekKey]!.add(watchman);
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
          '${monthFormatter.format(date)}${separator}${dayFormatter.format(date)}';
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
                ),
              ),
            ),
          ),

          // Date text
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              displayText,
              style: texts.labelLarge?.copyWith(
                color: accentColor,
                fontWeight: FontWeight.w600,
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
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Phone call functionality
  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri phoneUri = Uri(scheme: 'tel', path: phoneNumber);
    try {
      await launchUrl(phoneUri, mode: LaunchMode.platformDefault);
    } on PlatformException catch (e) {
      debugPrint('Failed to open dialer: ${e.message}');
    }
  }

  // WhatsApp functionality
  Future<void> _openWhatsApp(String phoneNumber, String watchmenName) async {
    try {
      // Remove any non-numeric characters except +
      final cleanNumber = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');

      // Ensure number has country code
      String formattedNumber =
          cleanNumber.startsWith('+') ? cleanNumber : '+$cleanNumber';

      final message = Uri.encodeComponent(
          'Hello $watchmenName, I hope you are doing well. I wanted to check in with you.');

      // Try direct app URL first
      final directAppUri = Uri.parse(
          'https://api.whatsapp.com/send?phone=$formattedNumber&text=$message');

      if (await canLaunchUrl(directAppUri)) {
        await launchUrl(
          directAppUri,
          mode: LaunchMode.externalApplication,
        );
        return;
      }

      // Fallback to native URI
      final nativeUri =
          Uri.parse('https://wa.me/$formattedNumber?text=$message');
      if (await canLaunchUrl(nativeUri)) {
        await launchUrl(
          nativeUri,
          mode: LaunchMode.externalApplication,
        );
        return;
      }

      // Last fallback to web WhatsApp
      final webUri = Uri.parse(
          'https://web.whatsapp.com/send?phone=$formattedNumber&text=$message');
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('WhatsApp error: $e');
      if (context.mounted) {
        _showToast(
          'Could not open WhatsApp. Please check if WhatsApp is installed.',
          Theme.of(context).colorScheme.error,
        );
      }
    }
  }

  void _showToast(String message, Color bgColor) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      timeInSecForIosWeb: 1,
      backgroundColor: bgColor,
      textColor: Colors.white,
    );
  }

  // Show delete confirmation dialog
  Future<void> _showDeleteConfirmation(
    WatchmenModel watchmen,
    WatchmenListViewModel vm,
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
              Icon(
                Icons.warning_amber_rounded,
                color: const Color(0xFFC81E1E),
                size: 28,
              ),
              const SizedBox(width: 12),
              Text(
                loc.translate('deleteWatchmen'),
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
                loc.translate('confirmDeleteWatchmen'),
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
                    Icon(
                      Icons.security_outlined,
                      size: 18,
                      color: const Color(0xFFC81E1E),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        watchmen.name.isNotEmpty
                            ? watchmen.name
                            : 'Unknown Watchmen',
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
                // Cancel Button
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

                // Delete Button
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
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.delete_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          loc.translate('delete'),
                          style: const TextStyle(
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
      if (watchmen.id != null) {
        await vm.deleteWatchmen(watchmen.id!, context);
      }
    }
  }
}

class _EnhancedWatchmenTile extends StatelessWidget {
  final WatchmenModel watchmen;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback onCall;
  final VoidCallback onWhatsApp;
  final AppLocalizations loc;
  final int index;

  const _EnhancedWatchmenTile({
    super.key,
    required this.watchmen,
    required this.onDelete,
    required this.onEdit,
    required this.onCall,
    required this.onWhatsApp,
    required this.loc,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;

    return Dismissible(
      key: Key('watchmen_${watchmen.id ?? index}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        onDelete();
        return false; // Don't dismiss automatically, let the confirmation dialog handle it
      },
      background: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFC72828),
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsetsDirectional.only(end: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.delete_outline,
              color: Colors.white,
              size: 28,
            ),
            const SizedBox(height: 4),
            Text(
              loc.translate('delete'),
              style: const TextStyle(
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

            // Disable press effects to avoid stuck highlight
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            overlayColor: WidgetStateProperty.all<Color>(Colors.transparent),

            onTap: () {
              // Navigate on next frame so pressed state clears
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) {
                  context.push('/watchmen-details', extra: watchmen);
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Watchmen Avatar
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.primary.withValues(alpha: 0.1),
                        ),
                        child: ClipOval(
                          child: SvgPicture.asset(
                            'assets/icons/WatchMen-Avatar.svg',
                            fit: BoxFit.cover,
                            width: 50,
                            height: 50,
                          ),
                        ),
                      ),

                      const SizedBox(width: 16),

                      // Watchmen Details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Watchmen Name
                            Row(
                              children: [
                                const Icon(
                                  Icons.person,
                                  size: 18,
                                  color: Colors.black,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    watchmen.name.isNotEmpty
                                        ? watchmen.name
                                        : loc.translate('unknownWatchmen'),
                                    style: texts.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: colors.onSurface,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  watchmen.createdAt != null
                                      ? _getFormattedDate(watchmen.createdAt!)
                                      : loc.translate('notSpecified'),
                                  style: texts.bodySmall?.copyWith(
                                    color:
                                        colors.onSurface.withValues(alpha: 0.6),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 6),
                            // Building Name and Location Row
                            Row(
                              children: [
                                // Building Name
                                Expanded(
                                  flex: 4,
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.apartment,
                                        size: 16,
                                        color: colors.onSurface
                                            .withValues(alpha: 0.8),
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          watchmen.buildingName.isNotEmpty
                                              ? watchmen.buildingName
                                              : loc.translate('noBuilding'),
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
                                ),

                                // Building Location
                                Expanded(
                                  flex: 6,
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.location_on_rounded,
                                        size: 16,
                                        color: colors.onSurface
                                            .withValues(alpha: 0.4),
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          watchmen.buildingLocation.isNotEmpty
                                              ? watchmen.buildingLocation
                                              : loc.translate('noLocation'),
                                          style: texts.bodyMedium?.copyWith(
                                            color: colors.onSurface
                                                .withValues(alpha: 0.6),
                                          ),
                                          overflow: TextOverflow.ellipsis,
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
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Contact Actions Row
                  Row(
                    children: [
                      // Call Button
                      Expanded(
                        child: Container(
                          height: 40,
                          decoration: BoxDecoration(
                            color: watchmen.phoneNumber.isNotEmpty
                                ? const Color(0xFFE8F5E8)
                                : colors.surfaceContainerHighest
                                    .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: watchmen.phoneNumber.isNotEmpty
                                  ? onCall
                                  : null,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    watchmen.phoneNumber.isNotEmpty
                                        ? Icons.phone
                                        : Icons.phone_disabled_rounded,
                                    color: watchmen.phoneNumber.isNotEmpty
                                        ? const Color(0xFF4CAF50)
                                        : colors.onSurfaceVariant
                                            .withValues(alpha: 0.5),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    loc.translate('call'),
                                    style: texts.bodyMedium?.copyWith(
                                      color: watchmen.phoneNumber.isNotEmpty
                                          ? const Color(0xFF4CAF50)
                                          : colors.onSurfaceVariant
                                              .withValues(alpha: 0.5),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 12),

                      // WhatsApp Button
                      Expanded(
                        child: Container(
                          height: 40,
                          decoration: BoxDecoration(
                            color: watchmen.phoneNumber.isNotEmpty
                                ? const Color(0xFFE8F5E8)
                                : colors.surfaceContainerHighest
                                    .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: watchmen.phoneNumber.isNotEmpty
                                  ? onWhatsApp
                                  : null,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Image.asset(
                                    watchmen.phoneNumber.isNotEmpty
                                        ? AppImages.whatsapp
                                        : AppImages.whatsAppDisable,
                                    width: 20,
                                    height: 20,
                                    color: watchmen.phoneNumber.isNotEmpty
                                        ? null
                                        : colors.onSurfaceVariant
                                            .withValues(alpha: 0.5),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    loc.translate('whatsapp'),
                                    style: texts.bodyMedium?.copyWith(
                                      color: watchmen.phoneNumber.isNotEmpty
                                          ? const Color(0xFF4CAF50)
                                          : colors.onSurfaceVariant
                                              .withValues(alpha: 0.5),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
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
    ); // End of Dismissible
  }

  String _getFormattedDate(DateTime date) {
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }
}

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
