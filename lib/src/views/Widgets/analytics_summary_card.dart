// lib/src/Views/Widgets/analytics_summary_card.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:broker_wallet/src/data/models/analytics_model.dart';
import 'package:broker_wallet/src/constants/app_colors.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';

/// Compact horizontal analytics card for home screen
/// Shows 3 key metrics in swipeable cards - tappable to navigate to full analytics
class AnalyticsSummaryCard extends StatelessWidget {
  final AnalyticsSummary summary;

  const AnalyticsSummaryCard({
    super.key,
    required this.summary,
  });

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);
    final isRTL = Directionality.of(context) == TextDirection.rtl;

    return GestureDetector(
      onTap: () => context.push('/analytics'),
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, 8),
              spreadRadius: -5,
            ),
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              // Glassmorphism effect
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.1),
                        Colors.white.withValues(alpha: 0.05),
                      ],
                    ),
                  ),
                ),
              ),

              // Content
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header with icon
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(
                            Icons.insights,
                            color: AppColors.primary,
                            size: 14,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          localization.translate('businessInsights'),
                          style: TextStyle(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                    ? Colors.white
                                    : Colors.black87,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          isRTL
                              ? Icons.arrow_back_ios
                              : Icons.arrow_forward_ios,
                          color: AppColors.primary.withValues(alpha: 0.7),
                          size: 14,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Metrics row (horizontal scroll for more metrics)
                    Expanded(
                      child: summary.isLoading
                          ? _buildLoadingState()
                          : _buildMetricsRow(localization),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricsRow(AppLocalizations localization) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _MetricItem(
          icon: Icons.home_work_outlined,
          value: summary.totalProperties.toString(),
          label: localization.translate('totalProperties'),
        ),
        _buildDivider(),
        _MetricItem(
          icon: Icons.attach_money,
          value: summary.portfolioValueFormatted,
          label: localization.translate('portfolioValue'),
          isCompact: true,
        ),
        _buildDivider(),
        _MetricItem(
          icon: Icons.pending_actions_outlined,
          value: summary.activeRequests.toString(),
          label: localization.translate('activeRequests'),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 40,
      color: AppColors.primary.withValues(alpha: 0.2),
    );
  }

  Widget _buildLoadingState() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildShimmerBox(),
        _buildShimmerBox(),
        _buildShimmerBox(),
      ],
    );
  }

  Widget _buildShimmerBox() {
    return Container(
      width: 60,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}

/// Individual metric display
class _MetricItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final bool isCompact;

  const _MetricItem({
    required this.icon,
    required this.value,
    required this.label,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = AppColors.primary;

    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: primaryColor,
            size: 16,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: isCompact ? 12 : 14,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: TextStyle(
              color: (isDark ? Colors.white : Colors.black87).withValues(alpha: 0.7),
              fontSize: 8,
              fontWeight: FontWeight.w400,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}
