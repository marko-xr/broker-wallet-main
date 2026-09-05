import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';

/// Widget to display current quota usage across all sections
class QuotaStatusCard extends StatelessWidget {
  const QuotaStatusCard({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUserId = context.watch<AuthViewModel>().currentUserId;
    if (currentUserId == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final texts = theme.textTheme;
    final localization = AppLocalizations.of(context);

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final plan = data?['plan'] as String? ?? 'free';
        final counts = data?['counts'] as Map<String, dynamic>? ?? {};
        final lifetimeCreated =
            data?['lifetimeCreated'] as Map<String, dynamic>? ?? {};

        final isPremium = plan != 'free';

        // Define main sections with localized labels
        final mainSections = [
          {
            'key': 'offers',
            'label': localization.translate('offers'),
            'icon': Icons.local_offer
          },
          {
            'key': 'requests',
            'label': localization.translate('requests'),
            'icon': Icons.request_page
          },
          {
            'key': 'owners',
            'label': localization.translate('owners'),
            'icon': Icons.person
          },
          {
            'key': 'offices',
            'label': localization.translate('offices'),
            'icon': Icons.business
          },
          {
            'key': 'brokers',
            'label': localization.translate('brokers'),
            'icon': Icons.badge
          },
          {
            'key': 'watchmen',
            'label': localization.translate('watchmen'),
            'icon': Icons.security
          },
          {
            'key': 'quotations',
            'label': localization.translate('quotations'),
            'icon': Icons.receipt
          },
        ];

        // Define toolkit tools with localized labels
        final toolkitTools = [
          {
            'key': 'scanner',
            'label': localization.translate('scanner'),
            'icon': Icons.document_scanner
          },
          {
            'key': 'signature',
            'label': localization.translate('signature'),
            'icon': Icons.draw
          },
          {
            'key': 'imageToPdf',
            'label': localization.translate('convertImagesToPdf'),
            'icon': Icons.picture_as_pdf
          },
          {
            'key': 'combinePdfs',
            'label': localization.translate('combinePdfs'),
            'icon': Icons.merge
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
        final totalLimit =
            isPremium ? null : 33; // 7 sections × 3 + 4 tools × 3

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          padding: const EdgeInsets.all(16),
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
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    isPremium ? Icons.workspace_premium : Icons.dashboard,
                    color: Colors.white,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isPremium
                              ? localization.translate('premiumPlan')
                              : localization.translate('freePlan'),
                          style: texts.titleLarge!.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          isPremium
                              ? localization
                                  .translate('unlimitedItemsAllSections')
                              : localization
                                  .translate('upToThreeItemsPerSection'),
                          style: texts.bodySmall!.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Total Usage
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${localization.translate('totalItems')}:',
                      style: texts.titleMedium!.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      isPremium
                          ? '$totalUsed ${localization.translate('items')}'
                          : '$totalUsed / $totalLimit ${localization.translate('items')}',
                      style: texts.titleMedium!.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              if (!isPremium) ...[
                const SizedBox(height: 12),
                // Progress bar for free users
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: totalLimit! > 0 ? totalUsed / totalLimit : 0,
                    minHeight: 8,
                    backgroundColor: Colors.white.withValues(alpha: 0.3),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      totalUsed >= totalLimit * 0.8
                          ? Colors.red.shade300
                          : Colors.green.shade300,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // Main Sections Title
              Row(
                children: [
                  Icon(
                    Icons.checklist,
                    color: Colors.white.withValues(alpha: 0.9),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    localization.translate('mainSections'),
                    style: texts.titleSmall!.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Main sections list
              ...mainSections.map((section) {
                final count = counts[section['key']] as int? ?? 0;
                final lifetimeCount =
                    lifetimeCreated[section['key']] as int? ?? 0;
                final limit = isPremium ? null : 3;
                // Highlight if user has reached lifetime limit (even if they deleted items)
                final hasReachedLimit = !isPremium && lifetimeCount >= 3;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        section['icon'] as IconData,
                        color: Colors.white.withValues(alpha: 0.8),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          section['label'] as String,
                          style: texts.bodyMedium!.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: hasReachedLimit
                              ? Colors.red.shade400.withValues(alpha: 0.3)
                              : Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isPremium ? '$count' : '$count / $limit',
                          style: texts.labelMedium!.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),

              const SizedBox(height: 16),

              // Elegant Divider
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 1,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            Colors.white.withValues(alpha: 0.3),
                            Colors.white.withValues(alpha: 0.3),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Toolkit Tools Title
              Row(
                children: [
                  Icon(
                    Icons.build_circle_outlined,
                    color: Colors.white.withValues(alpha: 0.9),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    localization.translate('toolkit'),
                    style: texts.titleSmall!.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Toolkit tools list
              ...toolkitTools.map((tool) {
                final count = counts[tool['key']] as int? ?? 0;
                final lifetimeCount = lifetimeCreated[tool['key']] as int? ?? 0;
                final limit = isPremium ? null : 3;
                // Highlight if user has reached lifetime limit (even if they deleted items)
                final hasReachedLimit = !isPremium && lifetimeCount >= 3;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        tool['icon'] as IconData,
                        color: Colors.white.withValues(alpha: 0.8),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tool['label'] as String,
                          style: texts.bodyMedium!.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: hasReachedLimit
                              ? Colors.red.shade400.withValues(alpha: 0.3)
                              : Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isPremium ? '$count' : '$count / $limit',
                          style: texts.labelMedium!.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ],
          ),
        );
      },
    );
  }
}
