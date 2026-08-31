import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:broker_wallet/src/common/utils/svg_icon.dart';
import 'package:go_router/go_router.dart';
import '../common/localization/localization_delegate.dart';
import '../data/models/ScreensModel/offers_model.dart';
import '../Views/Widgets/property_status_indicator.dart';

/// 🏠 Compact offer card widget for use in lists and carousels
/// Displays offer summary with property details, price, location, and status
class CompactOfferCard extends StatelessWidget {
  final OfferModel offer;
  final bool showShadow;
  final EdgeInsets? margin;

  const CompactOfferCard({
    super.key,
    required this.offer,
    this.showShadow = true,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;
    final loc = AppLocalizations.of(context);
    final isRent = offer.offerType == 'rent';
    final squareFootageValue = offer.squareFootage.trim();

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
                          SvgIcon.offersAvatar,
                          fit: BoxFit.cover,
                          width: 50,
                          height: 50,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

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
                                  _getPropertyTypeDisplay(offer, loc),
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
                                color: colors.onSurface.withValues(alpha: 0.8),
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  _getSpecificPropertyTypeDisplay(offer, loc),
                                  style: texts.bodySmall?.copyWith(
                                    color:
                                        colors.onSurface.withValues(alpha: 0.8),
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 40),
                              Icon(
                                Icons.location_on_rounded,
                                size: 16,
                                color: colors.onSurface.withValues(alpha: 0.6),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  _getCityDisplayName(offer.selectedCity, loc),
                                  style: texts.bodyMedium?.copyWith(
                                    color:
                                        colors.onSurface.withValues(alpha: 0.8),
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
                                  vertical: 5,
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
                                    const SizedBox(width: 2),
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
                                      const SizedBox(width: 2),
                                      Text(
                                        '$squareFootageValue ${loc.translate('squareFootageUnit')}',
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
                          // const SizedBox(height: 8),
                          // if (offer.minPrice.isNotEmpty ||
                          //     offer.maxPrice.isNotEmpty)
                          //   Container(
                          //     padding: const EdgeInsets.symmetric(
                          //       horizontal: 24,
                          //       vertical: 4,
                          //     ),
                          //     decoration: BoxDecoration(
                          //       color: colors.tertiary.withValues(alpha: 0.1),
                          //       borderRadius: BorderRadius.circular(20),
                          //       border: Border.all(
                          //         color: colors.tertiary.withValues(alpha: 0.3),
                          //         width: 1,
                          //       ),
                          //     ),
                          //     child: Row(
                          //       mainAxisSize: MainAxisSize.min,
                          //       children: [
                          //         Icon(
                          //           Icons.payments_rounded,
                          //           size: 12,
                          //           color: colors.tertiary,
                          //         ),
                          //         const SizedBox(width: 4),
                          //         Text(
                          //           _getPriceRange(offer, loc),
                          //           style: texts.labelSmall?.copyWith(
                          //             color: colors.tertiary,
                          //             fontWeight: FontWeight.w600,
                          //           ),
                          //         ),
                          //       ],
                          //     ),
                          //   ),
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

  // String _getPriceRange(OfferModel offer, AppLocalizations loc) {
  //   final min = offer.minPrice.trim();
  //   final max = offer.maxPrice.trim();

  //   if (min.isNotEmpty && max.isNotEmpty) {
  //     return '$min - $max ${loc.translate('aed')}';
  //   } else if (min.isNotEmpty) {
  //     return '${loc.translate('from')} $min ${loc.translate('aed')}';
  //   } else if (max.isNotEmpty) {
  //     return '${loc.translate('upTo')} $max ${loc.translate('aed')}';
  //   }
  //   return loc.translate('priceNotSpecified');
  // }

  String _getCityDisplayName(String city, AppLocalizations loc) {
    if (city.isEmpty) return loc.translate('noCitySelected');

    String cityKey = _cityLocalizationKey(city);
    String localized = loc.translate(cityKey);

    if (localized.startsWith('** ')) {
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
        return city;
    }
  }

  String _getFormattedDate(DateTime date) {
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }

  String _getPropertyTypeDisplay(OfferModel offer, AppLocalizations loc) {
    final propertyTypeRaw = (offer.propertyType ?? '').trim();

    if (propertyTypeRaw.isEmpty) {
      return loc.translate('propertyTypeNotSpecified');
    }

    switch (propertyTypeRaw.toLowerCase()) {
      case 'residential':
        return loc.translate('residential');
      case 'commercial':
        return loc.translate('commercial');
      default:
        return propertyTypeRaw;
    }
  }

  String _getSpecificPropertyTypeDisplay(
      OfferModel offer, AppLocalizations loc) {
    final specific = offer.specificPropertyType.trim();
    if (specific.isEmpty) {
      return loc.translate('typeNotSpecified');
    }

    // Try to localize common property types
    final locKey = specific.toLowerCase().replaceAll(' ', '');
    final localized = loc.translate(locKey);
    return localized.startsWith('** ') ? specific : localized;
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
