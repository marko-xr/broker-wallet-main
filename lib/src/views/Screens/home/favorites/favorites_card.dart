import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:provider/provider.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:broker_wallet/src/Views/Widgets/favorite_button.dart';
import 'package:broker_wallet/src/services/optimistic_favorites_service.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:intl/intl.dart';
import 'favorites_item_model.dart';
import '../../../../data/models/ScreensModel/offers_model.dart';
import '../../../../data/models/ScreensModel/request_model.dart';
import '../../../../data/models/ScreensModel/owners_model.dart';
import '../../../../data/models/ScreensModel/offices_model.dart';
import '../../../../data/models/ScreensModel/brokers_model.dart';
import '../../../../data/models/ScreensModel/watchmen_model.dart';

class _FieldData {
  final IconData icon;
  final String value;

  const _FieldData({
    required this.icon,
    required this.value,
  });
}

class FavoriteCard extends StatefulWidget {
  final FavoriteItem favorite;
  final VoidCallback? onRemoveFromFavorites;

  const FavoriteCard({
    super.key,
    required this.favorite,
    this.onRemoveFromFavorites,
  });

  @override
  State<FavoriteCard> createState() => _FavoriteCardState();
}

class _FavoriteCardState extends State<FavoriteCard>
    with TickerProviderStateMixin {
  late OptimisticFavoritesService _optimisticFavoritesService;
  late AnimationController _disappearController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<Offset> _slideAnimation;

  bool _isRemoving = false;

  @override
  void initState() {
    super.initState();
    _optimisticFavoritesService =
        Provider.of<OptimisticFavoritesService>(context, listen: false);

    // Initialize disappear animations
    _disappearController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _disappearController,
      curve: const Interval(0.0, 0.8, curve: Curves.easeOut),
    ));

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.8,
    ).animate(CurvedAnimation(
      parent: _disappearController,
      curve: const Interval(0.2, 1.0, curve: Curves.easeInOut),
    ));

    _slideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0.3, 0.0),
    ).animate(CurvedAnimation(
      parent: _disappearController,
      curve: const Interval(0.3, 1.0, curve: Curves.easeIn),
    ));

    // Initialize favorite status since we're in the favorites list,
    // we know this item is favorited initially
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _optimisticFavoritesService.initializeFavoriteStatus(
        widget.favorite.id,
        widget.favorite.type,
      );
    });
  }

  @override
  void dispose() {
    _disappearController.dispose();
    super.dispose();
  }

  Future<void> _handleRemoveFromFavorites() async {
    if (_isRemoving) return;

    setState(() {
      _isRemoving = true;
    });

    try {
      // Start disappear animation
      await _disappearController.forward();

      // Remove from favorites after animation completes
      await _optimisticFavoritesService.toggleFavorite(
        widget.favorite.id,
        widget.favorite.type,
      );

      // Call parent callback to remove from list
      if (widget.onRemoveFromFavorites != null) {
        widget.onRemoveFromFavorites!();
      }
    } catch (e) {
      // If error, reset animation and state
      setState(() {
        _isRemoving = false;
      });
      _disappearController.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final localization = AppLocalizations.of(context);
    final typeLabel = _localizedTypeLabel(localization);
    final dealLabel = _dealTypeLabel(localization);

    return AnimatedBuilder(
      animation: _disappearController,
      builder: (context, child) {
        return SlideTransition(
          position: _slideAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: RepaintBoundary(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: LinearGradient(
                      colors: [
                        colors.primary.withValues(alpha: 0.12),
                        colors.primary.withValues(alpha: 0.04),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: colors.shadow.withValues(alpha: 0.08),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                      BoxShadow(
                        color: colors.shadow.withValues(alpha: 0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: _isRemoving
                          ? null
                          : () => _navigateToDetails(context),
                      borderRadius: BorderRadius.circular(20),
                      splashColor: colors.primary.withValues(alpha: 0.1),
                      highlightColor: colors.primary.withValues(alpha: 0.05),
                      child: Container(
                        margin: const EdgeInsets.all(1.2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          color: colors.surface,
                          border: Border.all(
                            color: colors.outline.withValues(alpha: 0.08),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Image / Icon header with overlays (badge + favorite mark)
                            Expanded(
                              flex: 5,
                              child: Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: const BorderRadius.only(
                                      topLeft: Radius.circular(20),
                                      topRight: Radius.circular(20),
                                    ),
                                    child: _ImageOrFallback(
                                      imageUrl: widget.favorite.imageUrl,
                                      type: widget.favorite.type,
                                      typeIcon: widget.favorite.typeIcon,
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Colors.black.withValues(alpha: 0.05),
                                            Colors.black.withValues(alpha: 0.20),
                                          ],
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                        ),
                                      ),
                                    ),
                                  ),

                                  // Type badge (top-left)
                                  Positioned(
                                    top: 12,
                                    left: 12,
                                    child: _TypeBadge(
                                      label: typeLabel,
                                      secondaryLabel: dealLabel,
                                      color: _badgeColorForType(
                                          widget.favorite.type),
                                      labelColor: _badgeLabelColorForType(
                                          widget.favorite.type),
                                    ),
                                  ),

                                  // Animated favorite button (top-right)
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: Consumer<OptimisticFavoritesService>(
                                      builder: (context, optimisticService, _) {
                                        // In favorites list, items start as favorited
                                        final isLoading =
                                            optimisticService.isLoading(
                                                widget.favorite.id,
                                                widget.favorite.type);

                                        return OptimizedFavoriteButton(
                                          isFavorite:
                                              true, // Always true in favorites list initially
                                          isLoading: isLoading || _isRemoving,
                                          size: 18,
                                          showBackground: true,
                                          activeColor: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                          padding: const EdgeInsets.all(8),
                                          onToggle: _isRemoving
                                              ? null
                                              : _handleRemoveFromFavorites,
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Content
                            Expanded(
                              flex: 4,
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: _buildContentFields(
                                      context, localization),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildContentFields(
      BuildContext context, AppLocalizations localization) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final numberFormat =
        NumberFormat.decimalPattern(Localizations.localeOf(context).toString());

    switch (widget.favorite.type) {
      case 'requests':
        return _buildRequestFields(
            context, localization, textTheme, colors, numberFormat);
      case 'offers':
        return _buildOfferFields(
            context, localization, textTheme, colors, numberFormat);
      case 'owners':
        return _buildOwnerFields(context, localization, textTheme, colors);
      case 'offices':
        return _buildOfficeFields(context, localization, textTheme, colors);
      case 'brokers':
        return _buildBrokerFields(context, localization, textTheme, colors);
      case 'watchmen':
        return _buildWatchmenFields(context, localization, textTheme, colors);
      default:
        return _buildFallbackFields(context, localization, textTheme, colors);
    }
  }

  List<Widget> _buildRequestFields(
      BuildContext context,
      AppLocalizations localization,
      TextTheme textTheme,
      ColorScheme colors,
      NumberFormat numberFormat) {
    final request = widget.favorite.originalData as RequestModel?;
    return [
      _buildSingleFieldWithIcon(
          _FieldData(
            icon: Icons.home_rounded,
            value: request?.propertyType != null &&
                    request!.propertyType!.isNotEmpty
                ? _getLocalizedPropertyType(request.propertyType!, localization)
                : localization.translate('na'),
          ),
          textTheme,
          colors),
      const SizedBox(height: 6),
      _buildFieldRowWithIcons([
        _FieldData(
          icon: Icons.business_rounded,
          value: request != null && request.specificPropertyType.isNotEmpty
              ? _getLocalizedSpecificType(
                  request.specificPropertyType, localization)
              : localization.translate('na'),
        ),
        _FieldData(
          icon: Icons.square_foot,
          value: _formatSquareFeet(
              request?.squareFootage, numberFormat, localization),
        ),
      ], textTheme, colors),
      const SizedBox(height: 6),
      _buildSingleFieldWithIcon(
          _FieldData(
            icon: Icons.location_city_rounded,
            value: request != null && request.selectedCity.isNotEmpty
                ? _getLocalizedCityName(request.selectedCity, localization)
                : localization.translate('na'),
          ),
          textTheme,
          colors),
    ];
  }

  List<Widget> _buildOfferFields(
      BuildContext context,
      AppLocalizations localization,
      TextTheme textTheme,
      ColorScheme colors,
      NumberFormat numberFormat) {
    final offer = widget.favorite.originalData as OfferModel?;
    return [
      _buildSingleFieldWithIcon(
          _FieldData(
            icon: Icons.home_rounded,
            value: offer?.propertyType != null &&
                    offer!.propertyType!.isNotEmpty
                ? _getLocalizedPropertyType(offer.propertyType!, localization)
                : localization.translate('na'),
          ),
          textTheme,
          colors),
      const SizedBox(height: 6),
      _buildFieldRowWithIcons([
        _FieldData(
          icon: Icons.business_rounded,
          value: offer != null && offer.specificPropertyType.isNotEmpty
              ? _getLocalizedSpecificType(
                  offer.specificPropertyType, localization)
              : localization.translate('na'),
        ),
        _FieldData(
          icon: Icons.square_foot,
          value: _formatSquareFeet(
              offer?.squareFootage, numberFormat, localization),
        ),
      ], textTheme, colors),
      const SizedBox(height: 6),
      _buildSingleFieldWithIcon(
          _FieldData(
            icon: Icons.location_city_rounded,
            value: offer != null && offer.selectedCity.isNotEmpty
                ? _getLocalizedCityName(offer.selectedCity, localization)
                : localization.translate('na'),
          ),
          textTheme,
          colors),
    ];
  }

  List<Widget> _buildOwnerFields(BuildContext context,
      AppLocalizations localization, TextTheme textTheme, ColorScheme colors) {
    final owner = widget.favorite.originalData as OwnerModel?;
    return [
      _buildSingleFieldWithIcon(
          _FieldData(
            icon: Icons.person_rounded,
            value: owner?.name ?? localization.translate('na'),
          ),
          textTheme,
          colors),
      const SizedBox(height: 6),
      _buildFieldRowWithIcons([
        _FieldData(
          icon: Icons.business_rounded,
          value: owner?.typeOfProperties ?? localization.translate('na'),
        ),
        _FieldData(
          icon: Icons.location_on_rounded,
          value: owner?.propertyLocation ?? localization.translate('na'),
        ),
      ], textTheme, colors),
      const SizedBox(height: 6),
      _buildSingleFieldWithIcon(
          _FieldData(
            icon: Icons.phone_rounded,
            value: _formatPhoneNumber(owner?.phoneNumber),
          ),
          textTheme,
          colors),
    ];
  }

  List<Widget> _buildOfficeFields(BuildContext context,
      AppLocalizations localization, TextTheme textTheme, ColorScheme colors) {
    final office = widget.favorite.originalData as OfficeModel?;
    return [
      _buildSingleFieldWithIcon(
          _FieldData(
            icon: Icons.business_rounded,
            value: office?.officeName ?? localization.translate('na'),
          ),
          textTheme,
          colors),
      const SizedBox(height: 6),
      _buildSingleFieldWithIcon(
          _FieldData(
            icon: Icons.location_on_rounded,
            value: office?.officeLocation ?? localization.translate('na'),
          ),
          textTheme,
          colors),
      const SizedBox(height: 6),
      _buildSingleFieldWithIcon(
          _FieldData(
            icon: Icons.phone_rounded,
            value: _formatPhoneNumber(office?.phoneNumber),
          ),
          textTheme,
          colors),
    ];
  }

  List<Widget> _buildBrokerFields(BuildContext context,
      AppLocalizations localization, TextTheme textTheme, ColorScheme colors) {
    final broker = widget.favorite.originalData as BrokerModel?;
    final noteText =
        broker?.notes != null && broker!.notes.isNotEmpty ? broker.notes : null;

    List<Widget> fields = [
      _buildSingleFieldWithIcon(
          _FieldData(
            icon: Icons.person_rounded,
            value: broker?.name ?? localization.translate('na'),
          ),
          textTheme,
          colors),
      const SizedBox(height: 6),
      _buildSingleFieldWithIcon(
          _FieldData(
            icon: Icons.phone_rounded,
            value: _formatPhoneNumber(broker?.phoneNumber),
          ),
          textTheme,
          colors),
    ];

    if (noteText != null) {
      fields.addAll([
        const SizedBox(height: 6),
        _buildSingleFieldWithIcon(
            _FieldData(
              icon: Icons.note_alt_rounded,
              value: noteText,
            ),
            textTheme,
            colors,
            maxLines: 1),
      ]);
    }

    return fields;
  }

  List<Widget> _buildWatchmenFields(BuildContext context,
      AppLocalizations localization, TextTheme textTheme, ColorScheme colors) {
    final watchman = widget.favorite.originalData as WatchmenModel?;
    return [
      _buildSingleFieldWithIcon(
          _FieldData(
            icon: Icons.person_rounded,
            value: watchman?.name ?? localization.translate('na'),
          ),
          textTheme,
          colors),
      const SizedBox(height: 6),
      _buildSingleFieldWithIcon(
        _FieldData(
          icon: Icons.business_rounded,
          value: watchman?.buildingName ?? localization.translate('na'),
        ),
        textTheme,
        colors,
      ),
      const SizedBox(height: 6),
      _buildSingleFieldWithIcon(
          _FieldData(
            icon: Icons.phone_rounded,
            value: _formatPhoneNumber(watchman?.phoneNumber),
          ),
          textTheme,
          colors),
    ];
  }

  List<Widget> _buildFallbackFields(BuildContext context,
      AppLocalizations localization, TextTheme textTheme, ColorScheme colors) {
    return [
      _buildField(localization.translate('title'), widget.favorite.title,
          textTheme, colors),
      const SizedBox(height: 4),
      _buildField(localization.translate('details'), widget.favorite.subtitle,
          textTheme, colors,
          maxLines: 2),
    ];
  }

  Widget _buildFieldRowWithIcons(
      List<_FieldData> fieldData, TextTheme textTheme, ColorScheme colors) {
    final widgets = <Widget>[];

    // Check if the current locale is Arabic
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    // Use smaller spacing for Arabic due to compact letter width
    final fieldSpacing = isArabic ? 4.0 : 18.0;

    for (int i = 0; i < fieldData.length; i++) {
      final data = fieldData[i];

      widgets.add(
        Expanded(
          flex: i == 0 ? 3 : 3, // Give first field more space
          child: Container(
            alignment: AlignmentDirectional.centerStart,
            child: Row(
              children: [
                Icon(
                  data.icon,
                  size: 16,
                  color: colors.onSurface.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    data.value,
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.onSurface.withValues(alpha: 0.8),
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      // Add spacing between fields
      if (i < fieldData.length - 2) {
        widgets.add(SizedBox(width: fieldSpacing));
      }
    }

    return Row(children: widgets);
  }

  Widget _buildSingleFieldWithIcon(
      _FieldData data, TextTheme textTheme, ColorScheme colors,
      {int? maxLines}) {
    return Container(
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        children: [
          Icon(
            data.icon,
            size: 16,
            color: colors.onSurface.withValues(alpha: 0.6),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              data.value,
              style: textTheme.bodySmall?.copyWith(
                color: colors.onSurface.withValues(alpha: 0.8),
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: maxLines ?? 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField(
      String label, String value, TextTheme textTheme, ColorScheme colors,
      {int? maxLines}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: textTheme.labelSmall?.copyWith(
            color: colors.onSurface.withValues(alpha: 0.6),
            fontWeight: FontWeight.w600,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: maxLines ?? 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.bodySmall?.copyWith(
            color: colors.onSurface,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  String _formatPhoneNumber(
    String? phoneNumber,
  ) {
    if (phoneNumber == null || phoneNumber.isEmpty) {
      return AppLocalizations.of(context).translate('na');
    }

    return ' $phoneNumber';
  }

  String _formatSquareFeet(String? squareFeet, NumberFormat numberFormat,
      AppLocalizations localization) {
    if (squareFeet == null || squareFeet.isEmpty) {
      return localization.translate('na');
    }
    final parsed = double.tryParse(squareFeet);
    if (parsed == null) {
      return squareFeet;
    }
    return numberFormat.format(parsed);
  }

  void _navigateToDetails(BuildContext context) {
    switch (widget.favorite.type) {
      case 'offers':
        context.push('/offers-details', extra: widget.favorite.originalData);
        break;
      case 'requests':
        context.push('/requested-details', extra: widget.favorite.originalData);
        break;
      case 'owners':
        context.push('/owners-details', extra: widget.favorite.originalData);
        break;
      case 'offices':
        context.push('/offices-details', extra: widget.favorite.originalData);
        break;
      case 'brokers':
        context.push('/brokers-details', extra: widget.favorite.originalData);
        break;
      case 'watchmen':
        context.push('/watchmen-details', extra: widget.favorite.originalData);
        break;
    }
  }

  String _localizedTypeLabel(AppLocalizations localization) {
    switch (widget.favorite.type) {
      case 'offers':
        return localization.translate('offers');
      case 'requests':
        return localization.translate('requests');
      case 'owners':
        return localization.translate('owners');
      case 'offices':
        return localization.translate('offices');
      case 'brokers':
        return localization.translate('brokers');
      case 'watchmen':
        return localization.translate('watchmen');
      default:
        return localization.translate('favorites');
    }
  }

  String? _dealTypeLabel(AppLocalizations localization) {
    if (widget.favorite.type == 'offers') {
      final offer = widget.favorite.originalData as OfferModel?;
      final rawType = offer?.offerType ?? widget.favorite.title;
      return _mapDealTypeToLabel(rawType, localization);
    }
    if (widget.favorite.type == 'requests') {
      final request = widget.favorite.originalData as RequestModel?;
      final rawType = request?.requestType ?? widget.favorite.title;
      return _mapDealTypeToLabel(rawType, localization);
    }
    return null;
  }

  String? _mapDealTypeToLabel(String? rawType, AppLocalizations localization) {
    if (rawType == null) return null;
    final normalized = rawType.toLowerCase().trim();
    if (normalized.isEmpty) return null;

    if (normalized == 'rent' || normalized.contains('rent')) {
      return _localizedDealKeyword(localization, 'rent', 'Rent');
    }
    if (normalized == 'sell' ||
        normalized == 'sale' ||
        normalized.contains('sell') ||
        normalized.contains('sale')) {
      return _localizedDealKeyword(localization, 'sale', 'Sale');
    }
    return rawType;
  }

  String _localizedDealKeyword(
      AppLocalizations localization, String key, String fallback) {
    final translated = localization.translate(key);
    if (translated == '** $key not found') {
      return fallback;
    }
    return translated;
  }

  // Localization methods for property types, cities, and specific types
  String _getLocalizedPropertyType(
      String propertyType, AppLocalizations localization) {
    switch (propertyType.toLowerCase()) {
      case 'residential':
        return localization.translate('residential');
      case 'commercial':
        return localization.translate('commercial');
      case 'furnished':
        return localization.translate('furnished');
      default:
        return propertyType;
    }
  }

  String _getLocalizedSpecificType(
      String specificType, AppLocalizations localization) {
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
        return type;
    }
  }

  String _getLocalizedCityName(String city, AppLocalizations localization) {
    String cityKey = _cityLocalizationKey(city);
    String localizedCity = localization.translate(cityKey);

    // If translation not found, use original
    if (localizedCity == '** $cityKey not found') {
      return city;
    }
    return localizedCity;
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
}

/// Header image if available, otherwise a gradient panel with the entity SVG.
class _ImageOrFallback extends StatefulWidget {
  final String? imageUrl;
  final String
      type; // 'offers' | 'requests' | 'owners' | 'offices' | 'brokers' | 'watchmen'
  final String typeIcon; // asset path for the SVG icon

  const _ImageOrFallback({
    required this.imageUrl,
    required this.type,
    required this.typeIcon,
  });

  @override
  State<_ImageOrFallback> createState() => _ImageOrFallbackState();
}

class _ImageOrFallbackState extends State<_ImageOrFallback> {
  bool _imageLoaded = false;
  bool _imageExists = false;

  @override
  void initState() {
    super.initState();
    _checkImageCache();
  }

  bool _isValidNetworkUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.scheme == 'http' || uri.scheme == 'https';
    } catch (e) {
      return false;
    }
  }

  void _checkImageCache() {
    final hasImage =
        widget.imageUrl != null && widget.imageUrl!.trim().isNotEmpty;
    if (!hasImage) return;

    // Check if URL is a valid HTTP/HTTPS URL
    if (!_isValidNetworkUrl(widget.imageUrl!)) {
      setState(() {
        _imageLoaded = true;
        _imageExists = false;
      });
      return;
    }

    // Check if image is already in cache
    final imageProvider = CachedNetworkImageProvider(
      widget.imageUrl!,
      cacheKey: widget.imageUrl,
      maxWidth: 400,
      maxHeight: 300,
    );

    imageProvider.resolve(const ImageConfiguration()).addListener(
          ImageStreamListener(
            (image, synchronousCall) {
              if (mounted) {
                setState(() {
                  _imageLoaded = true;
                  _imageExists = true;
                });
              }
            },
            onError: (exception, stackTrace) {
              if (mounted) {
                setState(() {
                  _imageLoaded = true;
                  _imageExists = false;
                });
              }
            },
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final hasImage =
        widget.imageUrl != null && widget.imageUrl!.trim().isNotEmpty;

    if (!hasImage) {
      return _GradientIcon(type: widget.type, typeIcon: widget.typeIcon);
    }

    // For local:// URLs, skip the cache check and go directly to OfflineMediaService
    if (widget.imageUrl!.startsWith('local://')) {
      return OfflineMediaService.instance.buildOfflineAwareImage(
        imageUrl: widget.imageUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        placeholder:
            _GradientIcon(type: widget.type, typeIcon: widget.typeIcon),
        errorWidget:
            _GradientIcon(type: widget.type, typeIcon: widget.typeIcon),
      );
    }

    if (!_imageLoaded) {
      // Show SVG immediately while checking cache
      return _GradientIcon(type: widget.type, typeIcon: widget.typeIcon);
    }

    if (!_imageExists) {
      // Image failed to load, show SVG
      return _GradientIcon(type: widget.type, typeIcon: widget.typeIcon);
    }

    return OfflineMediaService.instance.buildOfflineAwareImage(
      imageUrl: widget.imageUrl!,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      placeholder: _GradientIcon(type: widget.type, typeIcon: widget.typeIcon),
      errorWidget: _GradientIcon(type: widget.type, typeIcon: widget.typeIcon),
    );
  }
}

/// Gradient + centered SVG icon (fallback)
class _GradientIcon extends StatelessWidget {
  final String type;
  final String typeIcon;

  const _GradientIcon({
    required this.type,
    required this.typeIcon,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _gradientForType(type);

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(16),
          ),
          child: SvgPicture.asset(
            typeIcon,
            width: 40,
            height: 40,
            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
          ),
        ),
      ),
    );
  }
}

class _TypeBadge extends StatefulWidget {
  final String label;
  final String? secondaryLabel;
  final Color color;
  final Color labelColor;

  const _TypeBadge({
    required this.label,
    this.secondaryLabel,
    required this.color,
    required this.labelColor,
  });

  @override
  State<_TypeBadge> createState() => _TypeBadgeState();
}

class _TypeBadgeState extends State<_TypeBadge> {
  static const _switchInterval = Duration(seconds: 2);
  static const double _horizontalPadding = 8;
  static const double _verticalPadding = 4;

  Timer? _timer;
  bool _showPrimary = true;

  @override
  void initState() {
    super.initState();
    _startTimerIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _TypeBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.label != widget.label ||
        oldWidget.secondaryLabel != widget.secondaryLabel) {
      _showPrimary = true;
      _startTimerIfNeeded();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimerIfNeeded() {
    _timer?.cancel();
    if (_hasSecondaryLabel) {
      _timer = Timer.periodic(_switchInterval, (_) {
        if (!mounted) return;
        setState(() {
          _showPrimary = !_showPrimary;
        });
      });
    }
  }

  bool get _hasSecondaryLabel {
    final secondary = widget.secondaryLabel;
    if (secondary == null) return false;
    final trimmed = secondary.trim();
    if (trimmed.isEmpty) return false;
    return trimmed.toLowerCase() != widget.label.trim().toLowerCase();
  }

  String get _displayLabel {
    if (!_hasSecondaryLabel) {
      return widget.label;
    }
    return _showPrimary ? widget.label : widget.secondaryLabel!.trim();
  }

  ValueKey<bool> get _labelKey => ValueKey<bool>(_showPrimary);

  @override
  Widget build(BuildContext context) {
    final baseStyle = Theme.of(context).textTheme.labelSmall ??
        const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, height: 1.2);
    final textStyle = baseStyle.copyWith(
      color: widget.labelColor,
      fontSize: 10,
      fontWeight: FontWeight.w700,
      height: 1.2,
    );
    final badgeWidth =
        _computeMaxLabelWidth(context, textStyle) + (_horizontalPadding * 2);

    return Container(
      width: badgeWidth,
      padding: const EdgeInsets.symmetric(
        horizontal: _horizontalPadding,
        vertical: _verticalPadding,
      ),
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        transitionBuilder: (child, animation) {
          final key = child.key;
          final isPrimary = key is ValueKey<bool> ? key.value : true;
          final beginOffset =
              isPrimary ? const Offset(-0.12, 0) : const Offset(0.12, 0);

          final slideAnimation = Tween<Offset>(
            begin: beginOffset,
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOut,
          ));

          return ClipRect(
            child: SlideTransition(
              position: slideAnimation,
              child: FadeTransition(
                opacity: animation,
                child: child,
              ),
            ),
          );
        },
        child: Text(
          _displayLabel,
          key: _labelKey,
          style: textStyle,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  double _computeMaxLabelWidth(BuildContext context, TextStyle style) {
    final labels = <String>[widget.label.trim()];
    final secondary = widget.secondaryLabel?.trim();
    if (secondary != null && secondary.isNotEmpty) {
      labels.add(secondary);
    }

    double maxWidth = 0;
    final textDirection = Directionality.of(context);

    for (final text in labels) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        maxLines: 1,
        textDirection: textDirection,
      )..layout();
      if (painter.width > maxWidth) {
        maxWidth = painter.width;
      }
    }

    return maxWidth;
  }
}

// ---------- Helpers ----------

Color _badgeColorForType(String type) {
  switch (type) {
    case 'requests':
      return const Color(0xFFEDE7FF);
    case 'offers':
      return const Color(0xFFE6F6EF);
    case 'owners':
      return const Color(0xFFFFEEE5);
    case 'offices':
      return const Color(0xFFE6EEFF);
    case 'brokers':
      return const Color(0xFFE8E7FF);
    case 'watchmen':
      return const Color(0xFFFFF9E3);
    default:
      return const Color(0xFFE5E7EB);
  }
}

Color _badgeLabelColorForType(String type) {
  switch (type) {
    case 'requests':
      return const Color(0xFF5B3CC4);
    case 'offers':
      return const Color(0xFF0B8A5F);
    case 'owners':
      return const Color(0xFFD8620F);
    case 'offices':
      return const Color(0xFF2563EB);
    case 'brokers':
      return const Color(0xFF4F46E5);
    case 'watchmen':
      return const Color(0xFFB5901D);
    default:
      return const Color(0xFF475569);
  }
}

List<Color> _gradientForType(String type) {
  switch (type) {
    case 'requests':
      return [const Color(0xFF6B46C1), const Color(0xFF8B5CF6)];
    case 'offers':
      return [const Color(0xFF059669), const Color(0xFF10B981)];
    case 'owners':
      return [const Color(0xFFEA580C), const Color(0xFFF97316)];
    case 'offices':
      return [const Color(0xFF2563EB), const Color(0xFF3B82F6)];
    case 'brokers':
      return [const Color(0xFF4F46E5), const Color(0xFF6D28D9)];
    case 'watchmen':
      return [const Color(0xFFEBE835), const Color(0xFFEAB308)];
    default:
      return const [Color(0xFF334155), Color(0xFF64748B)];
  }
}

// Shimmer skeleton for favorite cards
class FavoriteCardSkeleton extends StatelessWidget {
  const FavoriteCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            colors: [
              colors.primary.withValues(alpha: 0.10),
              colors.primary.withValues(alpha: 0.03),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: colors.shadow.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
              spreadRadius: 0,
            ),
            BoxShadow(
              color: colors.shadow.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
              spreadRadius: 0,
            ),
          ],
        ),
        child: Shimmer.fromColors(
          baseColor: colors.surfaceContainerHighest.withValues(alpha: 0.3),
          highlightColor: colors.surfaceContainerHighest.withValues(alpha: 0.1),
          child: Container(
            margin: const EdgeInsets.all(1.2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: colors.surface,
              border: Border.all(
                color: colors.outline.withValues(alpha: 0.08),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Image/Icon header
                Expanded(
                  flex: 5,
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(20),
                            topRight: Radius.circular(20),
                          ),
                          color: colors.surfaceContainerHighest
                              .withValues(alpha: 0.3),
                        ),
                      ),

                      // Type badge skeleton
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Container(
                          width: 60,
                          height: 20,
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),

                      // Favorite icon skeleton
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Content section
                Expanded(
                  flex: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title skeleton
                        Container(
                          width: double.infinity,
                          height: 16,
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 6),

                        // Subtitle skeleton
                        Container(
                          width: double.infinity,
                          height: 12,
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHighest
                                .withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 4),

                        // Second subtitle skeleton
                        Container(
                          width: 120,
                          height: 12,
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHighest
                                .withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
