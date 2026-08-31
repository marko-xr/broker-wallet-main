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
import '../../../data/models/ScreensModel/owners_model.dart';
import '../../../viewmodels/ListScreens/list_owners_viewmodel.dart';

class OwnersListView extends StatefulWidget {
  const OwnersListView({super.key});

  @override
  State<OwnersListView> createState() => _OwnersListViewState();
}

class _OwnersListViewState extends State<OwnersListView> {
  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;

    return ChangeNotifierProvider(
      create: (_) => OwnersListViewModel(),
      child: Consumer<OwnersListViewModel>(
        builder: (context, vm, _) {
          return Scaffold(
            backgroundColor: colors.surface,
            resizeToAvoidBottomInset: false,
            appBar: AppBar(
              leading: const BackArrowButton(),
              title: Text(
                loc.translate('owners'),
                style: texts.titleLarge,
              ),
              centerTitle: true,
              elevation: 0,
              backgroundColor: colors.surface,
            ),
            // Floating Action Button
            floatingActionButton: FloatingActionButton(
              onPressed: () => context.push('/add-owners'),
              backgroundColor: colors.primary,
              shape: const CircleBorder(),
              child: const Icon(Icons.add, color: Colors.white),
            ),

            // Content
            body: StreamBuilder<List<OwnerModel>>(
              stream: vm.ownersStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _buildShimmerLoading();
                }

                if (snapshot.hasError) {
                  return _buildErrorWidget(
                      vm, colors, texts, loc, snapshot.error.toString());
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return _buildEmptyWidget(colors, texts, loc);
                }

                return _buildOwnersListWithDateSeparators(
                    snapshot.data!, vm, loc, colors, texts);
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

  Widget _buildErrorWidget(OwnersListViewModel vm, ColorScheme colors,
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
                'assets/icons/owners-svg.svg',
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
              loc.translate('noOwnersYet'),
              style: texts.headlineSmall?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                loc.translate('addFirstOwner'),
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

  Widget _buildOwnersListWithDateSeparators(
    List<OwnerModel> owners,
    OwnersListViewModel vm,
    AppLocalizations loc,
    ColorScheme colors,
    TextTheme texts,
  ) {
    // Group owners by week
    final groupedOwners = _groupOwnersByWeek(owners);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // Statistics Card
        if (owners.isNotEmpty)
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.all(16),
              child: _buildStatisticsCard(owners, colors, texts, loc),
            ),
          ),

        // Generate slivers for each week group
        ...groupedOwners.entries.map((entry) {
          final weekKey = entry.key;
          final weekOwners = entry.value;

          return SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index == 0) {
                  return _buildDateSeparator(weekKey, colors, texts, loc);
                }

                // Adjust index for owner items
                final ownerIndex = index - 1;
                final owner = weekOwners[ownerIndex];

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: _EnhancedOwnerTile(
                      key: ValueKey('owner_${owner.id ?? ownerIndex}'),
                      owner: owner,
                      onDelete: () =>
                          _showDeleteConfirmation(owner, vm, loc, colors),
                      onEdit: () {
                        // Navigate to edit if needed
                      },
                      onCall: () => _makePhoneCall(owner.phoneNumber),
                      onWhatsApp: () =>
                          _openWhatsApp(owner.phoneNumber, owner.name),
                      loc: loc,
                      index: ownerIndex,
                    ),
                  ),
                );
              },
              childCount: weekOwners.length + 1, // +1 for date separator
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

  Widget _buildStatisticsCard(List<OwnerModel> owners, ColorScheme colors,
      TextTheme texts, AppLocalizations loc) {
    final totalOwners = owners.length;
    final ownersWithMedia = owners
        .where(
            (o) => o.uploadedFileName != null && o.uploadedFileName!.isNotEmpty)
        .length;

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
            child:
                const Icon(Icons.people_outline, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  totalOwners.toString(),
                  style: texts.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  loc.translate('totalOwners'),
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
                Icon(Icons.attachment, color: Colors.white, size: 20),
                const SizedBox(height: 4),
                Text(
                  '$ownersWithMedia',
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

  Map<String, List<OwnerModel>> _groupOwnersByWeek(List<OwnerModel> owners) {
    final Map<String, List<OwnerModel>> grouped = {};

    // Sort owners by creation date (newest first)
    final sortedOwners = List<OwnerModel>.from(owners);
    sortedOwners.sort((a, b) {
      final dateA = a.createdAt;
      final dateB = b.createdAt;
      return dateB.compareTo(dateA); // Newest first
    });

    for (final owner in sortedOwners) {
      final date = owner.createdAt;
      final weekKey = _getWeekKey(date);

      if (!grouped.containsKey(weekKey)) {
        grouped[weekKey] = [];
      }
      grouped[weekKey]!.add(owner);
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
  Future<void> _openWhatsApp(String phoneNumber, String ownerName) async {
    try {
      // Remove any non-numeric characters except +
      final cleanNumber = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');

      // Ensure number has country code
      String formattedNumber =
          cleanNumber.startsWith('+') ? cleanNumber : '+$cleanNumber';

      final message = Uri.encodeComponent(
          'Hello $ownerName, I saw your property listing and I\'m interested.');

      // Try direct native intent first
      final nativeUri =
          Uri.parse('https://wa.me/$formattedNumber?text=$message');

      // This is the key change: use this URL format instead
      final directAppUri = Uri.parse(
          'https://api.whatsapp.com/send?phone=$formattedNumber&text=$message');

      // Try direct app URL first
      if (await canLaunchUrl(directAppUri)) {
        await launchUrl(
          directAppUri,
          mode: LaunchMode.externalApplication,
        );
        return;
      }

      // Fallback to native URI
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
      // Show user-friendly error
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
    OwnerModel owner,
    OwnersListViewModel vm,
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
                loc.translate('deleteOwner'),
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
                loc.translate('confirmDeleteOwner'),
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
                      Icons.person_outline,
                      size: 18,
                      color: const Color(0xFFC81E1E),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        owner.name.isNotEmpty ? owner.name : 'Unknown Owner',
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
      if (owner.id != null) {
        await vm.deleteOwner(owner.id!, context);
      }
    }
  }
}

class _EnhancedOwnerTile extends StatelessWidget {
  final OwnerModel owner;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback onCall;
  final VoidCallback onWhatsApp;
  final AppLocalizations loc;
  final int index;

  const _EnhancedOwnerTile({
    super.key,
    required this.owner,
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
      key: Key('owner_${owner.id ?? index}'),
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
            Icon(
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
              // Delay one frame so InkWell can clear any pressed state
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) {
                  context.push('/owners-details', extra: owner);
                }
              });
            },

            child: Container(
              padding: const EdgeInsets.all(14),
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
                            'assets/icons/Owners-Avatar.svg',
                            fit: BoxFit.cover,
                            width: 50,
                            height: 50,
                          ),
                        ),
                      ),

                      const SizedBox(width: 16),

                      // Owner Details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Name
                            Row(
                              children: [
                                Icon(
                                  Icons.person,
                                  size: 18,
                                  color: Colors.black,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    owner.name.isNotEmpty
                                        ? owner.name
                                        : loc.translate('unknownOwner'),
                                    style: texts.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: colors.onSurface,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _getFormattedDate(owner.createdAt),
                                  style: texts.bodySmall?.copyWith(
                                    color:
                                        colors.onSurface.withValues(alpha: 0.6),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 4),

                            // Property Type and Location Row
                            Row(
                              children: [
                                // Property Type
                                Expanded(
                                  flex: 4,
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.business_rounded,
                                        size: 16,
                                        color: colors.onSurface
                                            .withValues(alpha: 0.8),
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          owner.typeOfProperties.isNotEmpty
                                              ? owner.typeOfProperties
                                              : loc.translate('noPropertyType'),
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

                                // Property Location
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
                                          owner.propertyLocation.isNotEmpty
                                              ? owner.propertyLocation
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
                            color: owner.phoneNumber.isNotEmpty
                                ? const Color(0xFFE8F5E8)
                                : colors.surfaceContainerHighest
                                    .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap:
                                  owner.phoneNumber.isNotEmpty ? onCall : null,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    owner.phoneNumber.isNotEmpty
                                        ? Icons.phone
                                        : Icons.phone_disabled_rounded,
                                    color: owner.phoneNumber.isNotEmpty
                                        ? const Color(0xFF4CAF50)
                                        : colors.onSurfaceVariant
                                            .withValues(alpha: 0.5),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    loc.translate('call'),
                                    style: texts.bodyMedium?.copyWith(
                                      color: owner.phoneNumber.isNotEmpty
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
                            color: owner.phoneNumber.isNotEmpty
                                ? const Color(0xFFE8F5E8)
                                : colors.surfaceContainerHighest
                                    .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: owner.phoneNumber.isNotEmpty
                                  ? onWhatsApp
                                  : null,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Image.asset(
                                    owner.phoneNumber.isNotEmpty
                                        ? AppImages.whatsapp
                                        : AppImages.whatsAppDisable,
                                    width: 20,
                                    height: 20,
                                    color: owner.phoneNumber.isNotEmpty
                                        ? null
                                        : colors.onSurfaceVariant
                                            .withValues(alpha: 0.5),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    loc.translate('whatsapp'),
                                    style: texts.bodyMedium?.copyWith(
                                      color: owner.phoneNumber.isNotEmpty
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
