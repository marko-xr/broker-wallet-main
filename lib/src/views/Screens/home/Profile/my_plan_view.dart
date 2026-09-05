// lib/src/Views/Screens/home/Profile/my_plan_view.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/Views/Widgets/back_arrow_button.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:broker_wallet/src/common/utils/svg_icon.dart';

/// Screen to display user's plan details and quota usage
class MyPlanView extends StatelessWidget {
  const MyPlanView({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUserId = context.watch<AuthViewModel>().currentUserId;
    if (currentUserId == null) {
      return const Scaffold(
        body: Center(child: Text('Please log in')),
      );
    }

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final texts = theme.textTheme;
    final localization = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        leading: const BackArrowButton(),
        title: Text(
          localization.translate('myPlan'),
          style: texts.headlineMedium!.copyWith(
            fontWeight: FontWeight.bold,
            color: colors.primary,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(currentUserId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data?.data() as Map<String, dynamic>?;
          final plan = data?['plan'] as String? ?? 'free';
          final counts = data?['counts'] as Map<String, dynamic>? ?? {};
          final lifetimeCreated =
              data?['lifetimeCreated'] as Map<String, dynamic>? ?? {};

          final isPremium = plan != 'free';

          // Define main sections with their icons (same as home screen)
          final mainSections = [
            {
              'key': 'offers',
              'label': localization.translate('offers'),
              'icon': SvgIcon.offersSvg
            },
            {
              'key': 'requests',
              'label': localization.translate('requests'),
              'icon': SvgIcon.requestedSvg
            },
            {
              'key': 'owners',
              'label': localization.translate('owners'),
              'icon': SvgIcon.ownersSvg
            },
            {
              'key': 'offices',
              'label': localization.translate('offices'),
              'icon': SvgIcon.officesSvg
            },
            {
              'key': 'brokers',
              'label': localization.translate('brokers'),
              'icon': SvgIcon.brokersSvg
            },
            {
              'key': 'watchmen',
              'label': localization.translate('watchmen'),
              'icon': SvgIcon.watchmanSvg
            },
            {
              'key': 'quotations',
              'label': localization.translate('quotations'),
              'icon': SvgIcon.quotationSvg
            },
          ];

          // Define toolkit tools with their icons (same as toolkit screen)
          final toolkitTools = [
            {
              'key': 'scanner',
              'label': localization.translate('scanner'),
              'icon': SvgIcon.scanIcon
            },
            {
              'key': 'signature',
              'label': localization.translate('signature'),
              'icon': SvgIcon.signatureIcon
            },
            {
              'key': 'imageToPdf',
              'label': localization.translate('convertImagesToPdf'),
              'icon': SvgIcon.galleryIcon
            },
            {
              'key': 'combinePdfs',
              'label': localization.translate('combinePdfs'),
              'icon': SvgIcon.combinePdfsIcon
            },
          ];

          // Calculate totals
          int totalUsed = 0;
          for (final section in mainSections) {
            totalUsed += (counts[section['key']] as int? ?? 0);
          }
          for (final tool in toolkitTools) {
            totalUsed += (counts[tool['key']] as int? ?? 0);
          }
          final totalLimit = isPremium ? null : 33;

          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Plan Status Card
                _buildPlanStatusCard(
                  context,
                  isPremium: isPremium,
                  plan: plan,
                  totalUsed: totalUsed,
                  totalLimit: totalLimit,
                ),
                const SizedBox(height: 24),

                // Main Sections Header
                Text(
                  localization.translate('mainSections'),
                  style: texts.titleLarge!.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 12),

                // Main Sections List
                _buildSectionsList(
                  context,
                  sections: mainSections,
                  counts: counts,
                  lifetimeCreated: lifetimeCreated,
                  isPremium: isPremium,
                ),
                const SizedBox(height: 24),

                // Toolkit Tools Header
                Text(
                  localization.translate('toolkitTools'),
                  style: texts.titleLarge!.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 12),

                // Toolkit Tools List
                _buildSectionsList(
                  context,
                  sections: toolkitTools,
                  counts: counts,
                  lifetimeCreated: lifetimeCreated,
                  isPremium: isPremium,
                ),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlanStatusCard(
    BuildContext context, {
    required bool isPremium,
    required String plan,
    required int totalUsed,
    required int? totalLimit,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final texts = theme.textTheme;
    final localization = AppLocalizations.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isPremium
              ? [Colors.purple.shade700, Colors.deepPurple.shade900]
              : [colors.primary.withValues(alpha: 0.8), colors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isPremium ? Icons.workspace_premium : Icons.card_membership,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isPremium
                          ? localization.translate('plusPlan')
                          : localization.translate('freePlan'),
                      style: texts.headlineSmall!.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _getLocalizedPlanName(context, plan),
                      style: texts.bodyMedium!.copyWith(
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              if (isPremium)
                const Icon(
                  Icons.verified,
                  color: Colors.amber,
                  size: 32,
                ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      localization.translate('totalUsage'),
                      style: texts.titleMedium!.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      isPremium
                          ? '$totalUsed / ${localization.translate('unlimited')}'
                          : '$totalUsed / $totalLimit',
                      style: texts.titleLarge!.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                if (!isPremium) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: totalLimit! > 0 ? totalUsed / totalLimit : 0,
                      backgroundColor: Colors.white.withValues(alpha: 0.3),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        totalUsed >= totalLimit
                            ? Colors.red.shade300
                            : Colors.white,
                      ),
                      minHeight: 8,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionsList(
    BuildContext context, {
    required List<Map<String, dynamic>> sections,
    required Map<String, dynamic> counts,
    required Map<String, dynamic> lifetimeCreated,
    required bool isPremium,
  }) {
    return Column(
      children: sections.map((section) {
        final key = section['key'] as String;
        final label = section['label'] as String;
        final icon = section['icon'] as String;

        final count = counts[key] as int? ?? 0;
        final lifetimeCount = lifetimeCreated[key] as int? ?? 0;
        final limit = 3;
        final hasReachedLimit = !isPremium && lifetimeCount >= limit;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildSectionListTile(
            context,
            icon: icon,
            label: label,
            count: count,
            limit: limit,
            hasReachedLimit: hasReachedLimit,
            isPremium: isPremium,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSectionListTile(
    BuildContext context, {
    required String icon,
    required String label,
    required int count,
    required int limit,
    required bool hasReachedLimit,
    required bool isPremium,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final texts = theme.textTheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasReachedLimit
              ? Colors.red.withValues(alpha: 0.3)
              : colors.primary.withValues(alpha: 0.1),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Icon with SVG support
          Container(
            width: 56,
            height: 56,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: hasReachedLimit
                  ? Colors.red.withValues(alpha: 0.1)
                  : colors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: SvgPicture.asset(
              icon,
              width: 32,
              height: 32,
              colorFilter: ColorFilter.mode(
                hasReachedLimit ? Colors.red : colors.primary,
                BlendMode.srcIn,
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Label
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: texts.titleMedium!.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  _getDescriptionText(
                    context,
                    count: count,
                    limit: limit,
                    hasReachedLimit: hasReachedLimit,
                    isPremium: isPremium,
                  ),
                  style: texts.bodySmall!.copyWith(
                    color: hasReachedLimit
                        ? Colors.red.shade700
                        : colors.onSurface.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Count badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: hasReachedLimit
                  ? Colors.red.shade400.withValues(alpha: 0.15)
                  : colors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              isPremium ? '$count' : '$count / $limit',
              style: texts.titleMedium!.copyWith(
                fontWeight: FontWeight.bold,
                color: hasReachedLimit ? Colors.red.shade700 : colors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getDescriptionText(
    BuildContext context, {
    required int count,
    required int limit,
    required bool hasReachedLimit,
    required bool isPremium,
  }) {
    final localization = AppLocalizations.of(context);

    if (isPremium) {
      // Premium users - show unlimited message
      return localization.translate('unlimitedItemsAvailable');
    }

    if (hasReachedLimit) {
      // User has reached lifetime limit
      return localization.translate('quotaLimitReached');
    }

    if (count == 0) {
      // No items added yet
      return localization.translate('youHaveThreeItemsAvailable');
    }

    // Show remaining slots
    final remaining = limit - count;
    if (remaining == 1) {
      return localization.translate('oneSlotRemaining');
    } else if (remaining == 2) {
      return localization.translate('twoSlotsRemaining');
    } else {
      return localization.translate('allSlotsUsed');
    }
  }

  /// Helper function to get localized plan name
  String _getLocalizedPlanName(BuildContext context, String plan) {
    final localization = AppLocalizations.of(context);
    final planLower = plan.toLowerCase();

    if (planLower == 'monthly') {
      return localization.translate('monthly');
    } else if (planLower == 'yearly') {
      return localization.translate('yearly');
    } else if (planLower == 'free') {
      return localization.translate('freePlan');
    } else {
      // Fallback for 'premium' or any other plan type
      return localization.translate('premiumPlan');
    }
  }
}
