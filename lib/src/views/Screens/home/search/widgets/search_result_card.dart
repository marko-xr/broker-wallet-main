import 'dart:async';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:broker_wallet/src/services/optimistic_favorites_service.dart';
import 'package:broker_wallet/src/Views/Screens/home/search/search_viewmodel.dart';
import 'package:broker_wallet/src/utils/text_highlighter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:broker_wallet/src/common/utils/svg_icon.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:broker_wallet/src/Views/Widgets/favorite_button.dart';

// Models (same as FavoriteCard uses)
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offices_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/brokers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/watchmen_model.dart';

class _FieldData {
  final IconData icon;
  final String value;
  const _FieldData({required this.icon, required this.value});
}

/// SearchResultCard — visual parity with FavoriteCard (clone of its UI)
class SearchResultCard extends StatefulWidget {
  final SearchResult result;
  final VoidCallback onTap;

  const SearchResultCard({
    super.key,
    required this.result,
    required this.onTap,
  });

  @override
  State<SearchResultCard> createState() => _SearchResultCardState();
}

class _SearchResultCardState extends State<SearchResultCard>
    with
        AutomaticKeepAliveClientMixin<SearchResultCard>,
        TickerProviderStateMixin {
  late final OptimisticFavoritesService _favoritesService;

  @override
  void initState() {
    super.initState();
    _favoritesService =
        Provider.of<OptimisticFavoritesService>(context, listen: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _favoritesService.initializeFavoriteStatus(
        widget.result.id,
        widget.result.favoriteTypeKey,
      );
    });
  }

  @override
  void didUpdateWidget(covariant SearchResultCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.result.id != widget.result.id ||
        oldWidget.result.type != widget.result.type) {
      _favoritesService.initializeFavoriteStatus(
        widget.result.id,
        widget.result.favoriteTypeKey,
      );
    }
  }

  Future<void> _handleToggleFavorite(OptimisticFavoritesService service) async {
    final loc = AppLocalizations.of(context);
    try {
      await service.toggleFavorite(
        widget.result.id,
        widget.result.favoriteTypeKey,
      );
    } catch (_) {
      if (!mounted) return;
      Fluttertoast.showToast(
        msg: loc.translate('favoritesErrorTitle'),
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
        fontSize: 14.0,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = Theme.of(context).colorScheme;
    final loc = AppLocalizations.of(context);

    final typeString = _favoriteTypeString(widget.result.type);
    final typeLabel = _localizedTypeLabel(typeString, loc);
    final dealLabel = _dealTypeLabel(widget.result, loc);
    final typeIcon = _typeIconForResultType(widget.result.type);

    return RepaintBoundary(
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
            onTap: widget.onTap,
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
                  // ===== Header (identical to FavoriteCard) =====
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
                            imageUrl: widget.result.imageUrl,
                            type: typeString,
                            typeIcon: typeIcon,
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
                            color: _badgeColorForType(typeString),
                            labelColor: _badgeLabelColorForType(typeString),
                          ),
                        ),
                        // Favorite button (top-right) — same visuals as FavoriteCard
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Consumer<OptimisticFavoritesService>(
                            builder: (context, service, _) {
                              final isFavorite = service.isFavorite(
                                widget.result.id,
                                widget.result.favoriteTypeKey,
                              );
                              final isLoading = service.isLoading(
                                widget.result.id,
                                widget.result.favoriteTypeKey,
                              );
                              return OptimizedFavoriteButton(
                                isFavorite: isFavorite,
                                isLoading: isLoading,
                                size: 18,
                                showBackground: true,
                                activeColor: colors.primary,
                                padding: const EdgeInsets.all(8),
                                onToggle: () => _handleToggleFavorite(service),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ===== Content (same fields/order as FavoriteCard) =====
                  Expanded(
                    flex: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: _SearchContentFields(
                        result: widget.result,
                        typeString: typeString,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

// ---------- Field content (clone of FavoriteCard logic) ----------

class _SearchContentFields extends StatelessWidget {
  final SearchResult result;
  final String typeString;

  const _SearchContentFields({
    required this.result,
    required this.typeString,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final loc = AppLocalizations.of(context);
    final numberFormat =
        NumberFormat.decimalPattern(Localizations.localeOf(context).toString());
    final searchQuery = result.searchQuery; // Get search query from result

    switch (typeString) {
      case 'requests':
        {
          final req = result.data as RequestModel?;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _singleFieldWithIcon(
                _FieldData(
                  icon: Icons.home_rounded,
                  value: (req?.propertyType != null &&
                          (req!.propertyType!.isNotEmpty))
                      ? _getLocalizedPropertyType(req.propertyType!, loc)
                      : loc.translate('na'),
                ),
                textTheme,
                colors,
                searchQuery: searchQuery,
              ),
              const SizedBox(height: 6),
              _fieldRowWithIcons([
                _FieldData(
                  icon: Icons.business_rounded,
                  value: (req != null && req.specificPropertyType.isNotEmpty)
                      ? _getLocalizedSpecificType(req.specificPropertyType, loc)
                      : loc.translate('na'),
                ),
                _FieldData(
                  icon: Icons.square_foot,
                  value:
                      _formatSquareFeet(req?.squareFootage, numberFormat, loc),
                ),
              ], textTheme, colors, searchQuery: searchQuery),
              const SizedBox(height: 6),
              _singleFieldWithIcon(
                _FieldData(
                  icon: Icons.location_city_rounded,
                  value: (req != null && req.selectedCity.isNotEmpty)
                      ? _getLocalizedCityName(req.selectedCity, loc)
                      : loc.translate('na'),
                ),
                textTheme,
                colors,
                searchQuery: searchQuery,
              ),
            ],
          );
        }
      case 'offers':
        {
          final offer = result.data as OfferModel?;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _singleFieldWithIcon(
                _FieldData(
                  icon: Icons.home_rounded,
                  value: (offer?.propertyType != null &&
                          (offer!.propertyType!.isNotEmpty))
                      ? _getLocalizedPropertyType(offer.propertyType!, loc)
                      : loc.translate('na'),
                ),
                textTheme,
                colors,
                searchQuery: searchQuery,
              ),
              const SizedBox(height: 6),
              _fieldRowWithIcons([
                _FieldData(
                  icon: Icons.business_rounded,
                  value:
                      (offer != null && offer.specificPropertyType.isNotEmpty)
                          ? _getLocalizedSpecificType(
                              offer.specificPropertyType, loc)
                          : loc.translate('na'),
                ),
                _FieldData(
                  icon: Icons.square_foot,
                  value: _formatSquareFeet(
                      offer?.squareFootage, numberFormat, loc),
                ),
              ], textTheme, colors, searchQuery: searchQuery),
              const SizedBox(height: 6),
              _singleFieldWithIcon(
                _FieldData(
                  icon: Icons.location_city_rounded,
                  value: (offer != null && offer.selectedCity.isNotEmpty)
                      ? _getLocalizedCityName(offer.selectedCity, loc)
                      : loc.translate('na'),
                ),
                textTheme,
                colors,
                searchQuery: searchQuery,
              ),
            ],
          );
        }
      case 'owners':
        {
          final owner = result.data as OwnerModel?;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _singleFieldWithIcon(
                _FieldData(
                  icon: Icons.person_rounded,
                  value: owner?.name ?? loc.translate('na'),
                ),
                textTheme,
                colors,
                searchQuery: searchQuery,
              ),
              const SizedBox(height: 6),
              _fieldRowWithIcons([
                _FieldData(
                  icon: Icons.business_rounded,
                  value: owner?.typeOfProperties ?? loc.translate('na'),
                ),
                _FieldData(
                  icon: Icons.location_on_rounded,
                  value: owner?.propertyLocation ?? loc.translate('na'),
                ),
              ], textTheme, colors, searchQuery: searchQuery),
              const SizedBox(height: 6),
              _singleFieldWithIcon(
                _FieldData(
                  icon: Icons.phone_rounded,
                  value: _formatPhoneNumber(owner?.phoneNumber, loc),
                ),
                textTheme,
                colors,
                searchQuery: searchQuery,
              ),
            ],
          );
        }
      case 'offices':
        {
          final office = result.data as OfficeModel?;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _singleFieldWithIcon(
                _FieldData(
                  icon: Icons.business_rounded,
                  value: office?.officeName ?? loc.translate('na'),
                ),
                textTheme,
                colors,
                searchQuery: searchQuery,
              ),
              const SizedBox(height: 6),
              _singleFieldWithIcon(
                _FieldData(
                  icon: Icons.location_on_rounded,
                  value: office?.officeLocation ?? loc.translate('na'),
                ),
                textTheme,
                colors,
                searchQuery: searchQuery,
              ),
              const SizedBox(height: 6),
              _singleFieldWithIcon(
                _FieldData(
                  icon: Icons.phone_rounded,
                  value: _formatPhoneNumber(office?.phoneNumber, loc),
                ),
                textTheme,
                colors,
                searchQuery: searchQuery,
              ),
            ],
          );
        }
      case 'brokers':
        {
          final broker = result.data as BrokerModel?;
          final noteText = (broker?.notes != null && broker!.notes.isNotEmpty)
              ? broker.notes
              : null;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _singleFieldWithIcon(
                _FieldData(
                  icon: Icons.person_rounded,
                  value: broker?.name ?? loc.translate('na'),
                ),
                textTheme,
                colors,
                searchQuery: searchQuery,
              ),
              const SizedBox(height: 6),
              _singleFieldWithIcon(
                _FieldData(
                  icon: Icons.phone_rounded,
                  value: _formatPhoneNumber(broker?.phoneNumber, loc),
                ),
                textTheme,
                colors,
                searchQuery: searchQuery,
              ),
              if (noteText != null) ...[
                const SizedBox(height: 6),
                _singleFieldWithIcon(
                  _FieldData(icon: Icons.note_alt_rounded, value: noteText),
                  textTheme,
                  colors,
                  maxLines: 1,
                  searchQuery: searchQuery,
                ),
              ],
            ],
          );
        }
      case 'watchmen':
        {
          final w = result.data as WatchmenModel?;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _singleFieldWithIcon(
                _FieldData(
                  icon: Icons.person_rounded,
                  value: w?.name ?? loc.translate('na'),
                ),
                textTheme,
                colors,
                searchQuery: searchQuery,
              ),
              const SizedBox(height: 6),
              _singleFieldWithIcon(
                _FieldData(
                  icon: Icons.business_rounded,
                  value: w?.buildingName ?? loc.translate('na'),
                ),
                textTheme,
                colors,
                searchQuery: searchQuery,
              ),
              const SizedBox(height: 6),
              _singleFieldWithIcon(
                _FieldData(
                  icon: Icons.phone_rounded,
                  value: _formatPhoneNumber(w?.phoneNumber, loc),
                ),
                textTheme,
                colors,
                searchQuery: searchQuery,
              ),
            ],
          );
        }
      default:
        {
          // Fallback if type unknown
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _singleFieldWithIcon(
                _FieldData(
                  icon: Icons.info_outline_rounded,
                  value: result.title,
                ),
                textTheme,
                colors,
                searchQuery: searchQuery,
              ),
              const SizedBox(height: 4),
              _singleFieldWithIcon(
                _FieldData(
                  icon: Icons.description_outlined,
                  value: result.subtitle,
                ),
                textTheme,
                colors,
                maxLines: 2,
                searchQuery: searchQuery,
              ),
            ],
          );
        }
    }
  }

  // ===== tiny UI helpers (identical to FavoriteCard) =====

  Widget _fieldRowWithIcons(
    List<_FieldData> fieldData,
    TextTheme textTheme,
    ColorScheme colors, {
    String? searchQuery,
  }) {
    return Row(
      children: fieldData.asMap().entries.map((entry) {
        final index = entry.key;
        final data = entry.value;
        return Expanded(
          child: Container(
            alignment: AlignmentDirectional.centerStart,
            child: Row(
              children: [
                Icon(data.icon,
                    size: 16, color: colors.onSurface.withValues(alpha: 0.6)),
                const SizedBox(width: 6),
                Expanded(
                  child: searchQuery != null && searchQuery.isNotEmpty
                      ? TextHighlighter.searchHighlight(
                          data.value,
                          searchQuery,
                          style: textTheme.bodySmall?.copyWith(
                            color: colors.onSurface.withValues(alpha: 0.8),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : Text(
                          data.value,
                          style: textTheme.bodySmall?.copyWith(
                            color: colors.onSurface.withValues(alpha: 0.8),
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                ),
                if (index < fieldData.length - 2) const SizedBox(width: 12),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _singleFieldWithIcon(
    _FieldData data,
    TextTheme textTheme,
    ColorScheme colors, {
    int? maxLines,
    String? searchQuery,
  }) {
    return Container(
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        children: [
          Icon(data.icon, size: 16, color: colors.onSurface.withValues(alpha: 0.6)),
          const SizedBox(width: 6),
          Expanded(
            child: searchQuery != null && searchQuery.isNotEmpty
                ? TextHighlighter.searchHighlight(
                    data.value,
                    searchQuery,
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.onSurface.withValues(alpha: 0.8),
                    ),
                    maxLines: maxLines ?? 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : Text(
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
}

// ---------- Helpers cloned from FavoriteCard ----------

String _formatPhoneNumber(String? phoneNumber, AppLocalizations loc) {
  if (phoneNumber == null || phoneNumber.isEmpty) {
    return loc.translate('na');
  }

  // Remove country code and format for local search-friendly display
  String formatted = phoneNumber;

  // Remove +971 country code if present
  if (formatted.startsWith('+971')) {
    formatted = formatted.substring(4); // Remove "+971"
  } else if (formatted.startsWith('971')) {
    formatted = formatted.substring(3); // Remove "971"
  }

  // Remove any spaces, dashes, or other formatting
  formatted = formatted.replaceAll(RegExp(r'[^\d]'), '');

  // Add leading 0 if not present (UAE local format)
  if (formatted.length >= 8 && !formatted.startsWith('0')) {
    formatted = '0$formatted';
  }

  return formatted;
}

String _formatSquareFeet(
  String? squareFeet,
  NumberFormat numberFormat,
  AppLocalizations localization,
) {
  if (squareFeet == null || squareFeet.isEmpty) {
    return localization.translate('na');
  }
  final parsed = double.tryParse(squareFeet);
  if (parsed == null) return squareFeet;
  return numberFormat.format(parsed);
}

String _getLocalizedPropertyType(
  String propertyType,
  AppLocalizations localization,
) {
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
  String specificType,
  AppLocalizations localization,
) {
  final key = _propertySubTypeKey(specificType);
  final localized = localization.translate(key);
  if (localized == '** $key not found') return specificType;
  return localized;
}

String _propertySubTypeKey(String type) {
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
      return "offices";
    default:
      return type;
  }
}

String _getLocalizedCityName(String city, AppLocalizations localization) {
  final key = _cityLocalizationKey(city);
  final localized = localization.translate(key);
  if (localized == '** $key not found') return city;
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

// Map SearchResultType to favorite type string
String _favoriteTypeString(SearchResultType type) {
  switch (type) {
    case SearchResultType.request:
      return 'requests';
    case SearchResultType.offer:
      return 'offers';
    case SearchResultType.owner:
      return 'owners';
    case SearchResultType.office:
      return 'offices';
    case SearchResultType.broker:
      return 'brokers';
    case SearchResultType.watchmen:
      return 'watchmen';
  }
}

String _localizedTypeLabel(String type, AppLocalizations loc) {
  switch (type) {
    case 'offers':
      return loc.translate('offers');
    case 'requests':
      return loc.translate('requests');
    case 'owners':
      return loc.translate('owners');
    case 'offices':
      return loc.translate('offices');
    case 'brokers':
      return loc.translate('brokers');
    case 'watchmen':
      return loc.translate('watchmen');
    default:
      return loc.translate('favorites');
  }
}

String? _dealTypeLabel(SearchResult result, AppLocalizations loc) {
  String? rawType;
  switch (result.type) {
    case SearchResultType.offer:
      final offer = result.data as OfferModel?;
      rawType = offer?.offerType ?? result.title;
      break;
    case SearchResultType.request:
      final request = result.data as RequestModel?;
      rawType = request?.requestType ?? result.title;
      break;
    default:
      break;
  }
  return _mapDealTypeToLabel(rawType, loc);
}

String? _mapDealTypeToLabel(String? rawType, AppLocalizations loc) {
  if (rawType == null) return null;
  final normalized = rawType.toLowerCase().trim();
  if (normalized.isEmpty) return null;

  if (normalized == 'rent' || normalized.contains('rent')) {
    return _localizedDealKeyword(loc, 'rent', 'Rent');
  }
  if (normalized == 'sell' ||
      normalized == 'sale' ||
      normalized.contains('sell') ||
      normalized.contains('sale')) {
    return _localizedDealKeyword(loc, 'sale', 'Sale');
  }
  return rawType;
}

String _localizedDealKeyword(
  AppLocalizations loc,
  String key,
  String fallback,
) {
  final translated = loc.translate(key);
  if (translated == '** $key not found') {
    return fallback;
  }
  return translated;
}

String _typeIconForResultType(SearchResultType type) {
  switch (type) {
    case SearchResultType.request:
      return SvgIcon.requestedSvg;
    case SearchResultType.offer:
      return SvgIcon.offersSvg;
    case SearchResultType.owner:
      return SvgIcon.ownersSvg;
    case SearchResultType.office:
      return SvgIcon.officesSvg;
    case SearchResultType.broker:
      return SvgIcon.brokersSvg;
    case SearchResultType.watchmen:
      return SvgIcon.watchmanSvg;
  }
}

// ---------- Header visual parts cloned from FavoriteCard ----------

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

    if (!_isValidNetworkUrl(widget.imageUrl!)) {
      setState(() {
        _imageLoaded = true;
        _imageExists = false;
      });
      return;
    }

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
      return _GradientIcon(type: widget.type, typeIcon: widget.typeIcon);
    }

    if (!_imageExists) {
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

// ----- Visual color helpers (same as FavoriteCard) -----

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
