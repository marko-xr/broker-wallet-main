import 'package:broker_wallet/src/common/utils/images.dart';
import 'package:flutter/material.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/brokers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offices_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/watchmen_model.dart';
import 'package:broker_wallet/src/Views/Widgets/property_status_indicator.dart';
import 'package:flutter_svg/svg.dart';
import 'package:broker_wallet/src/common/utils/svg_icon.dart';
import 'package:go_router/go_router.dart';

// Reusable Offer Tile for filtered view
class FilteredOfferTile extends StatelessWidget {
  final OfferModel offer;
  final AppLocalizations localization;
  final int index;
  final DateTime createdAt;

  const FilteredOfferTile({
    super.key,
    required this.offer,
    required this.localization,
    required this.index,
    required this.createdAt,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;
    final isRent = offer.offerType == 'rent';
    final squareFootageValue = offer.squareFootage.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
                          SvgIcon.offersAvatar,
                          fit: BoxFit.cover,
                          width: 50,
                          height: 50,
                        ),
                      ),
                    ),

                    const SizedBox(width: 20),

                    // Enhanced Content
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
                                _getFormattedDate(createdAt),
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
                                  _getSpecificPropertyTypeDisplay(offer),
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
                                  _getCityDisplayName(offer.selectedCity),
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
                                          ? localization.translate('rent')
                                          : localization.translate('sale'),
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
                                onTap: () {}, // Read-only in filtered view
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
                                      Text(
                                        '$squareFootageValue ${localization.translate('squareFootageUnit')}',
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
    );
  }

  String _getFormattedDate(DateTime date) {
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }

  String _getCityDisplayName(String city) {
    if (city.isEmpty) return localization.translate('noCitySelected');

    // Try to get localized city name
    String cityKey = _cityLocalizationKey(city);
    String localized = localization.translate(cityKey);

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

  String _getPropertyTypeDisplay(OfferModel offer) {
    final propertyTypeRaw = (offer.propertyType ?? '').trim();

    if (propertyTypeRaw.isEmpty) {
      return localization.translate('propertyTypeNotSpecified');
    }

    switch (propertyTypeRaw.toLowerCase()) {
      case 'residential':
        return localization.translate('residential');
      case 'commercial':
        return localization.translate('commercial');
      case 'furnished':
        return localization.translate('furnished');
      default:
        return propertyTypeRaw;
    }
  }

  String _getSpecificPropertyTypeDisplay(OfferModel offer) {
    final specificTypeRaw = offer.specificPropertyType.trim();
    if (specificTypeRaw.isEmpty) {
      return localization.translate('notSpecified');
    }
    return _getLocalizedSpecificType(specificTypeRaw);
  }

  String _getLocalizedSpecificType(String specificType) {
    // Convert spaces to camelCase for lookup in localization files
    String key = _propertySubTypeKey(specificType);
    String localized = localization.translate(key);

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
        return type; // fallback
    }
  }

  String _getPriceRange(OfferModel offer) {
    if (offer.minPrice.isNotEmpty && offer.maxPrice.isNotEmpty) {
      return '${offer.minPrice} - ${offer.maxPrice} ${localization.translate('aed')}';
    } else if (offer.minPrice.isNotEmpty) {
      return '${localization.translate('from')} ${offer.minPrice} ${localization.translate('aed')}';
    } else if (offer.maxPrice.isNotEmpty) {
      return '${localization.translate('upTo')} ${offer.maxPrice} ${localization.translate('aed')}';
    }
    return localization.translate('priceOnRequest');
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
}

// Reusable Request Tile for filtered view
class FilteredRequestTile extends StatelessWidget {
  final RequestModel request;
  final AppLocalizations localization;
  final int index;
  final DateTime createdAt;

  const FilteredRequestTile({
    super.key,
    required this.request,
    required this.localization,
    required this.index,
    required this.createdAt,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;
    final isRent = request.requestType == 'rent';
    final squareFootageValue = request.squareFootage.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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

                    const SizedBox(width: 20),

                    // Enhanced Content
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Property Type with icon
                          Row(
                            children: [
                              Icon(
                                _getPropertyIcon(request.propertyType),
                                size: 18,
                                color: Colors.black,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  _getPropertyTypeDisplay(request),
                                  style: texts.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: colors.onSurface,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _getFormattedDate(createdAt),
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
                                  _getSpecificPropertyTypeDisplay(request),
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
                                  _getCityDisplayName(request.selectedCity),
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
                            spacing: 6,
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
                                      request.requestType == 'rent'
                                          ? localization.translate('rent')
                                          : localization.translate('sale'),
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
                                status: request.status,
                                onTap: () {}, // Read-only in filtered view
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
                                      Text(
                                        '$squareFootageValue ${localization.translate('squareFootageUnit')}',
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
                          if (request.minPrice.isNotEmpty ||
                              request.maxPrice.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 4,
                              ),
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
                                  Text(
                                    _getPriceRange(request),
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
    );
  }

  String _getFormattedDate(DateTime date) {
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }

  String _getCityDisplayName(String city) {
    if (city.isEmpty) return localization.translate('noCitySelected');

    // Try to get localized city name
    String cityKey = _cityLocalizationKey(city);
    String localized = localization.translate(cityKey);

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

  String _getPropertyTypeDisplay(RequestModel request) {
    final propertyTypeRaw = (request.propertyType ?? '').trim();

    if (propertyTypeRaw.isEmpty) {
      return localization.translate('propertyTypeNotSpecified');
    }

    switch (propertyTypeRaw.toLowerCase()) {
      case 'residential':
        return localization.translate('residential');
      case 'commercial':
        return localization.translate('commercial');
      case 'furnished':
        return localization.translate('furnished');
      default:
        return propertyTypeRaw;
    }
  }

  String _getSpecificPropertyTypeDisplay(RequestModel request) {
    final specificTypeRaw = request.specificPropertyType.trim();
    if (specificTypeRaw.isEmpty) {
      return localization.translate('notSpecified');
    }
    return _getLocalizedSpecificType(specificTypeRaw);
  }

  String _getLocalizedSpecificType(String specificType) {
    // Convert to localization key format
    String key = _propertySubTypeKey(specificType);
    String localized = localization.translate(key);

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
        return type; // fallback
    }
  }

  String _getPriceRange(RequestModel request) {
    if (request.minPrice.isNotEmpty && request.maxPrice.isNotEmpty) {
      return '${request.minPrice} - ${request.maxPrice} ${localization.translate('aed')}';
    } else if (request.minPrice.isNotEmpty) {
      return '${localization.translate('from')} ${request.minPrice} ${localization.translate('aed')}';
    } else if (request.maxPrice.isNotEmpty) {
      return '${localization.translate('upTo')} ${request.maxPrice} ${localization.translate('aed')}';
    }
    return localization.translate('priceOnRequest');
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
}

// Reusable Owner Tile for filtered view
class FilteredOwnerTile extends StatelessWidget {
  final OwnerModel owner;
  final AppLocalizations localization;
  final int index;
  final DateTime createdAt;

  const FilteredOwnerTile({
    super.key,
    required this.owner,
    required this.localization,
    required this.index,
    required this.createdAt,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
                          SvgIcon.ownersAvatar,
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
                                      : localization.translate('unknownOwner'),
                                  style: texts.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: colors.onSurface,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _getFormattedDate(createdAt),
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
                                            : localization
                                                .translate('noPropertyType'),
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
                                            : localization
                                                .translate('noLocation'),
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
                          color: const Color(0xFFE8F5E8),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              // Call functionality - would need to be implemented in filtered view context
                            },
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.phone,
                                  color: Color(0xFF4CAF50),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  localization.translate('call'),
                                  style: texts.bodyMedium?.copyWith(
                                    color: const Color(0xFF4CAF50),
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
                          color: const Color(0xFFE8F5E8),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              // WhatsApp functionality - would need to be implemented in filtered view context
                            },
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Image.asset(
                                  AppImages.whatsapp,
                                  width: 20,
                                  height: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  localization.translate('whatsapp'),
                                  style: texts.bodyMedium?.copyWith(
                                    color: const Color(0xFF4CAF50),
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
    );
  }

  String _getFormattedDate(DateTime date) {
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }
}

// Reusable Office Tile for filtered view
class FilteredOfficeTile extends StatelessWidget {
  final OfficeModel office;
  final AppLocalizations localization;
  final int index;
  final DateTime createdAt;

  const FilteredOfficeTile({
    super.key,
    required this.office,
    required this.localization,
    required this.index,
    required this.createdAt,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
                          SvgIcon.officesAvatar,
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
                                      : localization.translate('unknownOffice'),
                                  style: texts.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: colors.onSurface,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _getFormattedDate(createdAt),
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
                                            : localization
                                                .translate('noManager'),
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
                                            : localization
                                                .translate('noLocation'),
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
                          color: const Color(0xFFE8F5E8),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              // Call functionality - would need to be implemented in filtered view context
                            },
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.phone,
                                  color: Color(0xFF4CAF50),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  localization.translate('call'),
                                  style: texts.bodyMedium?.copyWith(
                                    color: const Color(0xFF4CAF50),
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
                          color: const Color(0xFFE8F5E8),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              // WhatsApp functionality - would need to be implemented in filtered view context
                            },
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Image.asset(
                                  AppImages.whatsapp,
                                  width: 20,
                                  height: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  localization.translate('whatsapp'),
                                  style: texts.bodyMedium?.copyWith(
                                    color: const Color(0xFF4CAF50),
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
    );
  }

  String _getFormattedDate(DateTime date) {
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }
}

// Reusable Broker Tile for filtered view
class FilteredBrokerTile extends StatelessWidget {
  final BrokerModel broker;
  final AppLocalizations localization;
  final int index;
  final DateTime createdAt;

  const FilteredBrokerTile({
    super.key,
    required this.broker,
    required this.localization,
    required this.index,
    required this.createdAt,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
                context.push('/brokers-details', extra: broker);
              }
            });
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  children: [
                    // Broker Icon
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.primary.withValues(alpha: 0.1),
                      ),
                      child: ClipOval(
                        child: SvgPicture.asset(
                          SvgIcon.brokersAvatar,
                          fit: BoxFit.cover,
                          width: 50,
                          height: 50,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Broker Details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Broker Name
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
                                  broker.name.isNotEmpty
                                      ? broker.name
                                      : localization.translate('unknownBroker'),
                                  style: texts.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: colors.onSurface,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _getFormattedDate(createdAt),
                                style: texts.bodySmall?.copyWith(
                                  color:
                                      colors.onSurface.withValues(alpha: 0.6),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 8),

                          // Phone Number
                          Row(
                            children: [
                              Icon(
                                Icons.phone,
                                size: 16,
                                color: colors.onSurface.withValues(alpha: 0.6),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  broker.phoneNumber.isNotEmpty
                                      ? broker.phoneNumber
                                      : localization.translate('noPhoneNumber'),
                                  style: texts.bodyMedium?.copyWith(
                                    color:
                                        colors.onSurface.withValues(alpha: 0.8),
                                  ),
                                  overflow: TextOverflow.ellipsis,
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
                          color: const Color(0xFFE8F5E8),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              // Call functionality - would need to be implemented in filtered view context
                            },
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.phone,
                                  color: Color(0xFF4CAF50),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  localization.translate('call'),
                                  style: texts.bodyMedium?.copyWith(
                                    color: const Color(0xFF4CAF50),
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
                          color: const Color(0xFFE8F5E8),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              // WhatsApp functionality - would need to be implemented in filtered view context
                            },
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Image.asset(
                                  AppImages.whatsapp,
                                  width: 20,
                                  height: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  localization.translate('whatsapp'),
                                  style: texts.bodyMedium?.copyWith(
                                    color: const Color(0xFF4CAF50),
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
    );
  }

  String _getFormattedDate(DateTime date) {
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }
}

// Reusable Watchmen Tile for filtered view
class FilteredWatchmenTile extends StatelessWidget {
  final WatchmenModel watchmen;
  final AppLocalizations localization;
  final int index;
  final DateTime createdAt;

  const FilteredWatchmenTile({
    super.key,
    required this.watchmen,
    required this.localization,
    required this.index,
    required this.createdAt,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
                          SvgIcon.watchMenAvatar,
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
                                      : localization
                                          .translate('unknownWatchmen'),
                                  style: texts.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: colors.onSurface,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _getFormattedDate(createdAt),
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
                                            : localization
                                                .translate('noBuilding'),
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
                                            : localization
                                                .translate('noLocation'),
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
                          color: const Color(0xFFE8F5E8),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              // Call functionality - would need to be implemented in filtered view context
                            },
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.phone,
                                  color: Color(0xFF4CAF50),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  localization.translate('call'),
                                  style: texts.bodyMedium?.copyWith(
                                    color: const Color(0xFF4CAF50),
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
                          color: const Color(0xFFE8F5E8),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              // WhatsApp functionality - would need to be implemented in filtered view context
                            },
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Image.asset(
                                  AppImages.whatsapp,
                                  width: 20,
                                  height: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  localization.translate('whatsapp'),
                                  style: texts.bodyMedium?.copyWith(
                                    color: const Color(0xFF4CAF50),
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
    );
  }

  String _getFormattedDate(DateTime date) {
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }
}
