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

import '../../../data/models/ScreensModel/offices_model.dart';
import '../../../viewmodels/ListScreens/list_offices_viewmodel.dart';

class OfficesListView extends StatefulWidget {
  const OfficesListView({super.key});

  @override
  State<OfficesListView> createState() => _OfficesListViewState();
}

class _OfficesListViewState extends State<OfficesListView> {
  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;

    return ChangeNotifierProvider(
      create: (_) => OfficesListViewModel(),
      child: Consumer<OfficesListViewModel>(
        builder: (context, vm, _) {
          return Scaffold(
            backgroundColor: colors.surface,
            resizeToAvoidBottomInset: false,
            appBar: AppBar(
              leading: const BackArrowButton(),
              title: Text(
                loc.translate('offices'),
                style: texts.titleLarge,
              ),
              centerTitle: true,
              elevation: 0,
              backgroundColor: colors.surface,
            ),
            // Floating Action Button
            floatingActionButton: FloatingActionButton(
              onPressed: () => context.push('/add-offices'),
              backgroundColor: colors.primary,
              shape: const CircleBorder(),
              child: const Icon(Icons.add, color: Colors.white),
            ),

            // Content
            body: StreamBuilder<List<OfficeModel>>(
              stream: vm.officesStream,
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

                return _buildOfficesListWithDateSeparators(
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

  Widget _buildErrorWidget(OfficesListViewModel vm, ColorScheme colors,
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
                'assets/icons/offices-svg.svg',
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
              loc.translate('noOfficesYet'),
              style: texts.headlineSmall?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                loc.translate('addFirstOffice'),
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

  Widget _buildOfficesListWithDateSeparators(
    List<OfficeModel> offices,
    OfficesListViewModel vm,
    AppLocalizations loc,
    ColorScheme colors,
    TextTheme texts,
  ) {
    // Group offices by week
    final groupedOffices = _groupOfficesByWeek(offices);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // Statistics Card
        if (offices.isNotEmpty)
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.all(16),
              child: _buildStatisticsCard(offices, colors, texts, loc),
            ),
          ),

        // Generate slivers for each week group
        ...groupedOffices.entries.map((entry) {
          final weekKey = entry.key;
          final weekOffices = entry.value;

          return SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index == 0) {
                  return _buildDateSeparator(weekKey, colors, texts, loc);
                }

                // Adjust index for office items
                final officeIndex = index - 1;
                final office = weekOffices[officeIndex];

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: _EnhancedOfficeTile(
                      key: ValueKey('office_${office.id ?? officeIndex}'),
                      office: office,
                      onDelete: () =>
                          _showDeleteConfirmation(office, vm, loc, colors),
                      onEdit: () {
                        // Navigate to edit if needed
                      },
                      onCall: () => _makePhoneCall(office.phoneNumber),
                      onWhatsApp: () =>
                          _openWhatsApp(office.phoneNumber, office.managerName),
                      loc: loc,
                      index: officeIndex,
                    ),
                  ),
                );
              },
              childCount: weekOffices.length + 1, // +1 for date separator
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

  Widget _buildStatisticsCard(List<OfficeModel> offices, ColorScheme colors,
      TextTheme texts, AppLocalizations loc) {
    final totalOffices = offices.length;
    final officesWithNotes = offices.where((o) => o.notes.isNotEmpty).length;

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
            child: const Icon(Icons.business_outlined,
                color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  totalOffices.toString(),
                  style: texts.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  loc.translate('totalOffices'),
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
                  '$officesWithNotes',
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

  Map<String, List<OfficeModel>> _groupOfficesByWeek(
      List<OfficeModel> offices) {
    final Map<String, List<OfficeModel>> grouped = {};

    // Sort offices by creation date (newest first)
    final sortedOffices = List<OfficeModel>.from(offices);
    sortedOffices.sort((a, b) {
      final dateA = a.createdAt ?? DateTime.now();
      final dateB = b.createdAt ?? DateTime.now();
      return dateB.compareTo(dateA); // Newest first
    });

    for (final office in sortedOffices) {
      final date = office.createdAt ?? DateTime.now();
      final weekKey = _getWeekKey(date);

      if (!grouped.containsKey(weekKey)) {
        grouped[weekKey] = [];
      }
      grouped[weekKey]!.add(office);
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
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
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
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
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
  Future<void> _openWhatsApp(String phoneNumber, String managerName) async {
    try {
      // Remove any non-numeric characters except +
      final cleanNumber = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');

      // Ensure number has country code
      String formattedNumber =
          cleanNumber.startsWith('+') ? cleanNumber : '+$cleanNumber';

      final message = Uri.encodeComponent(
          'Hello $managerName, I would like to discuss business opportunities with your office.');

      // Try direct app URL first
      final directAppUri = Uri.parse(
          'https://api.whatsapp.com/send?phone=$formattedNumber&text=%22$message%22');

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
    OfficeModel office,
    OfficesListViewModel vm,
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
                loc.translate('deleteOffice'),
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
                loc.translate('confirmDeleteOffice'),
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
                      Icons.business_outlined,
                      size: 18,
                      color: const Color(0xFFC81E1E),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        office.officeName.isNotEmpty
                            ? office.officeName
                            : 'Unknown Office',
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
      if (office.id != null) {
        await vm.deleteOffice(office.id!, context);
      }
    }
  }
}

class _EnhancedOfficeTile extends StatelessWidget {
  final OfficeModel office;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback onCall;
  final VoidCallback onWhatsApp;
  final AppLocalizations loc;
  final int index;

  const _EnhancedOfficeTile({
    super.key,
    required this.office,
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
    final isRTL = Directionality.of(context).toString().contains('rtl');

    return Dismissible(
      key: Key('office_${office.id ?? index}'),
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
        alignment: isRTL ? Alignment.centerLeft : Alignment.centerRight,
        padding: EdgeInsets.only(
          left: isRTL ? 20 : 0,
          right: isRTL ? 0 : 20,
        ),
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
              // delay one frame so InkWell clears pressed state before navigating
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) {
                  context.push('/offices-details', extra: office);
                }
              });
            },

            child: Container(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Office Avatar
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.primary.withValues(alpha: 0.1),
                        ),
                        child: ClipOval(
                          child: SvgPicture.asset(
                            'assets/icons/Offices-Avatar.svg',
                            fit: BoxFit.cover,
                            width: 50,
                            height: 50,
                          ),
                        ),
                      ),

                      const SizedBox(width: 16),

                      // Office Details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Office Name
                            Row(
                              children: [
                                Icon(
                                  Icons.business,
                                  size: 16,
                                  color: colors.primary,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    office.officeName.isNotEmpty
                                        ? office.officeName
                                        : loc.translate('unknownOffice'),
                                    style: texts.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: colors.onSurface,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  office.createdAt != null
                                      ? _getFormattedDate(office.createdAt!)
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
                            // Manager Name and Location Row
                            Row(
                              children: [
                                // Manager Name
                                Expanded(
                                  flex: 4,
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.person_outline,
                                        size: 16,
                                        color: colors.onSurface
                                            .withValues(alpha: 0.8),
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          office.managerName.isNotEmpty
                                              ? office.managerName
                                              : loc.translate('noManager'),
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

                                // Office Location
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
                                          office.officeLocation.isNotEmpty
                                              ? office.officeLocation
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
                            color: office.phoneNumber.isNotEmpty
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
                                  office.phoneNumber.isNotEmpty ? onCall : null,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    office.phoneNumber.isNotEmpty
                                        ? Icons.phone
                                        : Icons.phone_disabled_rounded,
                                    color: office.phoneNumber.isNotEmpty
                                        ? const Color(0xFF4CAF50)
                                        : colors.onSurfaceVariant
                                            .withValues(alpha: 0.5),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    loc.translate('call'),
                                    style: texts.bodyMedium?.copyWith(
                                      color: office.phoneNumber.isNotEmpty
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
                            color: office.phoneNumber.isNotEmpty
                                ? const Color(0xFFE8F5E8)
                                : colors.surfaceContainerHighest
                                    .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: office.phoneNumber.isNotEmpty
                                  ? onWhatsApp
                                  : null,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Image.asset(
                                    office.phoneNumber.isNotEmpty
                                        ? AppImages.whatsapp
                                        : AppImages.whatsAppDisable,
                                    width: 20,
                                    height: 20,
                                    color: office.phoneNumber.isNotEmpty
                                        ? null
                                        : colors.onSurfaceVariant
                                            .withValues(alpha: 0.5),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    loc.translate('whatsapp'),
                                    style: texts.bodyMedium?.copyWith(
                                      color: office.phoneNumber.isNotEmpty
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
