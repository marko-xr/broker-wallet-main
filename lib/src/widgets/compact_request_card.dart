import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:broker_wallet/src/common/utils/svg_icon.dart';
import 'package:go_router/go_router.dart';
import '../common/localization/localization_delegate.dart';
import '../views/Screens/ViewDetails/widgets/offer_details_style.dart';
import '../data/models/ScreensModel/request_model.dart';
import '../views/Widgets/property_status_indicator.dart';
import 'compact_property_labels.dart';

/// 🔍 Compact request card widget for use in lists and carousels
/// Displays request summary with property details, price, location, and status
class CompactRequestCard extends StatelessWidget {
  final RequestModel request;
  final bool showShadow;
  final EdgeInsets? margin;

  const CompactRequestCard({
    super.key,
    required this.request,
    this.showShadow = true,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;
    final loc = AppLocalizations.of(context);
    final isRent = request.requestType == 'rent';
    final typeForeground =
        isRent ? OfferDetailsStyle.primaryButtonForeground : Colors.white;
    final squareFootageValue = request.squareFootage.trim();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
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
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: colors.tertiary.withValues(alpha: 0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                  spreadRadius: 0,
                ),
              ]
            : null,
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
                context.push('/requested-details', extra: request);
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
                          SvgIcon.requestedAvatar,
                          fit: BoxFit.cover,
                          width: 50,
                          height: 50,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Content
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(_getPropertyIcon(request.propertyType),
                                  size: 18, color: colors.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  CompactPropertyLabels.category(
                                      request.propertyType, loc),
                                  style: texts.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: colors.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Text(_getFormattedDate(request.createdAt),
                                  style: texts.bodySmall),
                              Text(
                                CompactPropertyLabels.subtype(
                                    request.specificPropertyType, loc),
                                  style: texts.bodySmall),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.location_on_rounded,
                                      size: 16, color: colors.onSurfaceVariant),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                        CompactPropertyLabels.city(
                                            request.selectedCity, loc),
                                        style: texts.bodyMedium),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Enhanced badges row
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              // Request Type Badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 5),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: isRent
                                        ? OfferDetailsStyle.rentBadgeGradient(
                                            colors)
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
                                      color: typeForeground,
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        isRent
                                            ? loc.translate('rent')
                                            : loc.translate('sale'),
                                        style: texts.labelSmall?.copyWith(
                                          color: typeForeground,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Status indicator
                              PropertyStatusChip(
                                status: request.status,
                                onTap: null, // Read-only in carousel
                              ),

                              if (squareFootageValue.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        colors.primary.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color:
                                          colors.primary.withValues(alpha: 0.2),
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
                                      Flexible(
                                          child: Text(
                                        '$squareFootageValue ${loc.translate('squareFootageUnit')}',
                                        style: texts.labelSmall?.copyWith(
                                          color: colors.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      )),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Price range badge if available
                          if (request.minPrice.isNotEmpty ||
                              request.maxPrice.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 4),
                              decoration: BoxDecoration(
                                color: colors.tertiary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: colors.tertiary.withValues(alpha: 0.3),
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
                                  Flexible(
                                      child: Text(
                                    _getPriceRange(request, loc),
                                    style: texts.labelSmall?.copyWith(
                                      color: colors.tertiary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  )),
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
    );
  }

  String _getPriceRange(RequestModel request, AppLocalizations loc) {
    final min = request.minPrice.trim();
    final max = request.maxPrice.trim();

    if (min.isNotEmpty && max.isNotEmpty) {
      return '$min - $max ${loc.translate('aed')}';
    } else if (min.isNotEmpty) {
      return '${loc.translate('from')} $min ${loc.translate('aed')}';
    } else if (max.isNotEmpty) {
      return '${loc.translate('upTo')} $max ${loc.translate('aed')}';
    }
    return loc.translate('priceNotSpecified');
  }

  String _getFormattedDate(DateTime date) {
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }

  IconData _getPropertyIcon(String? propertyType) {
    switch (propertyType?.toLowerCase()) {
      case 'residential':
        return Icons.home_rounded;
      case 'commercial':
        return Icons.business_rounded;
      default:
        return Icons.apartment_rounded;
    }
  }
}
