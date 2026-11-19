import 'package:broker_wallet/src/services/share/share_sources.dart';
import 'package:broker_wallet/src/views/Widgets/share_options_dialog.dart';
import 'package:broker_wallet/src/Views/Widgets/property_status_indicator.dart';
import 'package:broker_wallet/src/common/data/room_count.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/utils/svg_icon.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';
import 'package:broker_wallet/src/data/models/property_status.dart';
import 'package:broker_wallet/src/services/ScreenServices/request_service.dart';
import 'package:broker_wallet/src/services/optimistic_favorites_service.dart';
import 'package:broker_wallet/src/Views/Widgets/favorite_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:broker_wallet/src/services/phone_input_service.dart';
import 'package:broker_wallet/src/services/details_contact_actions.dart';
import 'package:intl/intl.dart';

import 'widgets/details_page.dart';
import 'widgets/details_section.dart';
import 'widgets/offer_details_style.dart';
import 'package:broker_wallet/src/views/Widgets/delete_confirmation_dialog.dart';

class RequestDetailsView extends StatefulWidget {
  final RequestModel request;

  const RequestDetailsView({
    super.key,
    required this.request,
  });

  @override
  State<RequestDetailsView> createState() => _RequestDetailsViewState();
}

class _RequestDetailsViewState extends State<RequestDetailsView>
    with TickerProviderStateMixin {
  late AnimationController _mainAnimationController;
  late AnimationController _fabAnimationController;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _fabAnimation;

  final ScrollController _scrollController = ScrollController();

  // Services
  final RequestService _requestService = RequestService();

  // Favorite state - now managed by OptimisticFavoritesService
  late OptimisticFavoritesService _optimisticFavoritesService;

  // Track current request data (may be updated after edit)
  late RequestModel _currentRequest;

  @override
  void initState() {
    super.initState();
    _currentRequest = widget.request; // Initialize with the passed request
    _optimisticFavoritesService =
        Provider.of<OptimisticFavoritesService>(context, listen: false);
    _setupAnimations();
  }

  void _setupAnimations() {
    _mainAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _fabAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _slideAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _mainAnimationController,
      curve: const Interval(0.0, 0.6, curve: Curves.fastOutSlowIn),
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _mainAnimationController,
      curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
    ));

    _fabAnimation = CurvedAnimation(
      parent: _fabAnimationController,
      curve: Curves.elasticOut,
    );

    // Start animations with delay for smooth entrance
    Future.microtask(() {
      _mainAnimationController.forward();
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) _fabAnimationController.forward();
      });
    });
  }

  @override
  void dispose() {
    _mainAnimationController.dispose();
    _fabAnimationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final phone = _currentRequest.phoneNumber;
    final canContact = DetailsContactActions.normalizePhone(phone,
            countryCode: _currentRequest.countryCode) !=
        null;
    return DetailsPage(
      title: loc.translate('requestDetails'),
      favorite: Consumer<OptimisticFavoritesService>(builder: _buildFavorite),
      onShare: _shareRequest,
      onEdit: _editRequest,
      onDelete: _showDeleteConfirmation,
      deleteLabel: loc.translate('deleteRequest'),
      onWhatsApp: !canContact ? null : () => _openWhatsApp(phone),
      onCall: !canContact ? null : () => _makePhoneCall(phone),
      scrollController: _scrollController,
      fade: _fadeAnimation,
      slide: _slideAnimation,
      contactFade: _fabAnimation,
      media: _buildRequestHeader,
      content: _buildCompactContent,
    );
  }

  Widget _buildFavorite(BuildContext context,
      OptimisticFavoritesService favorites, Widget? child) {
    final id = _currentRequest.id;
    if (id == null) {
      return const Icon(Icons.favorite_border, size: 18);
    }
    return OptimizedFavoriteButton(
      size: 18,
      padding: const EdgeInsets.all((kMinInteractiveDimension - 18) / 2),
      isFavorite: favorites.isRequestFavorite(id),
      isLoading: favorites.isRequestLoading(id),
      onToggle: _toggleFavorite,
    );
  }

  Widget _buildRequestHeader(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final scale = OfferDetailsStyle.scale(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(18 * scale),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: 160 + MediaQuery.textScalerOf(context).scale(48) - 48,
        ),
        child: AspectRatio(
          aspectRatio: 2.1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Material(
                color: Color.alphaBlend(
                  colors.primary.withValues(alpha: 0.06),
                  colors.surfaceContainerHighest,
                ),
                child: Center(
                  child: ColorFiltered(
                    colorFilter:
                        ColorFilter.mode(colors.primary, BlendMode.srcIn),
                    child: SvgPicture.asset(
                      SvgIcon.requestedSvg,
                      width: 56,
                      height: 56,
                      excludeFromSemantics: true,
                    ),
                  ),
                ),
              ),
              PositionedDirectional(
                top: 8,
                start: 8,
                end: 8,
                child: Align(
                  alignment: AlignmentDirectional.topStart,
                  child: _buildStatusBadge(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background = Color.alphaBlend(
        colors.primary.withValues(alpha: 0.12), colors.surfaceContainerLowest);
    final foreground = OfferDetailsStyle.accentText(colors, background);
    return DetailsStatusBadge(
      key: const ValueKey('request-details-status'),
      background: background,
      onTap: _currentRequest.id == null ? null : _showStatusSelector,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_statusIcon(_currentRequest.status),
              size: 12, color: foreground),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              _getLocalizedStatusLabel(),
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: foreground),
            ),
          ),
          // Tapping changes the status: say so, as a dropdown does.
          if (_currentRequest.id != null) ...[
            const SizedBox(width: 2),
            Icon(Icons.keyboard_arrow_down, size: 16, color: foreground),
          ],
        ]),
      ),
    );
  }

  Widget _buildCompactContent(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final rent = _currentRequest.requestType == 'rent';
    final location = _getLocationText();
    final property = _getPropertyDisplayText();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(builder: (context, constraints) {
          final summary = DetailsSummary(
            title: property.isNotEmpty
                ? property
                : loc.translate('propertyTypeNotSpecified'),
            titleMissing: property.isEmpty,
            subtitle: location.trim().isEmpty ? null : location,
          );
          final price = _buildPriceDisplay(context);
          if (constraints.maxWidth < 328 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.3) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                summary,
                const SizedBox(height: DetailsSection.spacing),
                price,
              ],
            );
          }
          return Row(children: [
            Expanded(child: summary),
            const SizedBox(width: 10),
            Expanded(child: price),
          ]);
        }),
        const SizedBox(height: DetailsSection.spacing),
        _buildPropertyStats(context),
        const SizedBox(height: DetailsSection.spacing),
        DetailsFields(
          title: loc.translate('requestRequirements'),
          rows: [
            DetailsField(
              icon: Icons.sell_outlined,
              label: loc.translate('request'),
              value: loc.translate(rent ? 'rentRequest' : 'saleRequest'),
            ),
            DetailsField(
              icon: Icons.location_city_outlined,
              label: loc.translate('city'),
              isMissing: _currentRequest.selectedCity.trim().isEmpty,
              value: _currentRequest.selectedCity.trim().isNotEmpty
                  ? _getLocalizedCityName(_currentRequest.selectedCity)
                  : loc.translate('cityNotSpecified'),
            ),
            DetailsField(
              icon: Icons.place_outlined,
              label: loc.translate('areas'),
              isMissing: _currentRequest.selectedAreas.isEmpty,
              value: _currentRequest.selectedAreas.isNotEmpty
                  ? _getLocalizedAreasText(_currentRequest.selectedAreas)
                  : loc.translate('areasNotSpecified'),
            ),
            DetailsField(
              icon: Icons.phone_outlined,
              label: loc.translate('phoneNumber'),
              isMissing: _currentRequest.phoneNumber.trim().isEmpty,
              value: _currentRequest.phoneNumber.trim().isNotEmpty
                  ? PhoneInputService.formatForDisplay(
                      _currentRequest.phoneNumber)
                  : loc.translate('phoneNotAdded'),
              onCopy: _currentRequest.phoneNumber.trim().isNotEmpty
                  ? _copyPhone
                  : null,
            ),
            if (_currentRequest.location.isNotEmpty)
              DetailsField(
                icon: Icons.map_outlined,
                label: loc.translate('specificLocation'),
                value: _currentRequest.location,
              ),
            ...DetailsDates.fields(context,
                createdAt: _currentRequest.createdAt,
                updatedAt: _currentRequest.updatedAt),
          ],
        ),
        if (_currentRequest.notes.isNotEmpty) ...[
          const SizedBox(height: DetailsSection.spacing),
          DetailsNotes(notes: _currentRequest.notes),
        ],
      ],
    );
  }

  // WhatsApp functionality
  Future<void> _openWhatsApp(String phoneNumber) async {
    final loc = AppLocalizations.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    final result = await DetailsContactActions.whatsApp(phoneNumber,
        countryCode: _currentRequest.countryCode);
    if (!mounted || result == ContactLaunchResult.opened) return;
    _showToast(
        loc.translate(result == ContactLaunchResult.invalidPhone
            ? 'phoneNumberNotAvailable'
            : 'couldNotOpenWhatsApp'),
        errorColor);
  }

  Widget _buildPriceDisplay(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context);
    final min = _currentRequest.minPrice;
    final max = _currentRequest.maxPrice;
    final currency = loc.translate('aed');
    final String price;
    if (min.isNotEmpty && max.isNotEmpty) {
      price = '$min – $max $currency';
    } else if (min.isNotEmpty) {
      price = '${loc.translate('from')} $min $currency';
    } else if (max.isNotEmpty) {
      price = '${loc.translate('upTo')} $max $currency';
    } else {
      price = loc.translate('budgetNotSpecified');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(loc.translate('requestBudget'), style: theme.textTheme.bodySmall),
        Text(price,
            style: theme.textTheme.titleLarge?.copyWith(
              color: min.isEmpty && max.isEmpty
                  ? theme.colorScheme.onSurfaceVariant
                  : OfferDetailsStyle.accentText(
                      theme.colorScheme, theme.colorScheme.surface),
            )),
      ],
    );
  }

  String _formatSquareFootage(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final numericPortion = trimmed.replaceAll(RegExp(r'[^0-9.,]'), '');
    if (numericPortion.isEmpty) {
      return trimmed;
    }

    final normalized = numericPortion.replaceAll(',', '');
    final parsed = double.tryParse(normalized);
    if (parsed == null) {
      return trimmed;
    }

    final formatter = NumberFormat.decimalPattern();
    return formatter.format(parsed);
  }

  Widget _buildPropertyStats(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;
    final loc = AppLocalizations.of(context);
    final stats = <Widget>[
      if (_shouldShowRoomsAndBaths()) ...[
        _buildStatItem(
            Icons.bed_outlined,
            RoomCount.display(_currentRequest.rooms),
            loc.translate('rooms'),
            colors,
            texts),
        _buildStatItem(
            Icons.bathtub_outlined,
            _currentRequest.bathrooms.toString(),
            loc.translate('bathrooms'),
            colors,
            texts),
      ],
      _buildStatItem(
          Icons.square_foot,
          _currentRequest.squareFootage.trim().isEmpty
              ? loc.translate('squareFootageNotSpecified')
              : '${_formatSquareFootage(_currentRequest.squareFootage)} ${loc.translate('squareFootageUnit')}',
          loc.translate('squareFootage'),
          colors,
          texts),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(
            color: colors.onSurface.withValues(alpha: 0.08), width: 0.7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final stacked = constraints.maxWidth < 300 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.5;
        if (stacked) return Column(children: stats);
        return IntrinsicHeight(
            child: Row(children: [
          for (var i = 0; i < stats.length; i++) ...[
            if (i > 0)
              VerticalDivider(
                  width: 1,
                  thickness: 0.5,
                  color: colors.onSurface.withValues(alpha: 0.12),
                  indent: 5,
                  endIndent: 5),
            Expanded(child: stats[i]),
          ],
        ]));
      }),
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label,
      ColorScheme colors, TextTheme texts) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 20, color: colors.primary),
        const SizedBox(height: 3),
        Text(label,
            textAlign: TextAlign.center,
            style: texts.bodySmall?.copyWith(height: 1.2)),
        const SizedBox(height: 2),
        Text(value,
            textAlign: TextAlign.center,
            style: texts.titleMedium?.copyWith(
                fontSize: 14 * OfferDetailsStyle.scale(context), height: 1.1)),
      ]),
    );
  }

  // Action methods
  Future<void> _toggleFavorite() async {
    if (_currentRequest.id == null) return;

    // Capture theme colors before async operation
    final loc = AppLocalizations.of(context);
    final primaryColor = Theme.of(context).colorScheme.primary;
    final onSurfaceColor = Theme.of(context).colorScheme.onSurface;
    final errorColor = Theme.of(context).colorScheme.error;

    try {
      final newFavoriteStatus = await _optimisticFavoritesService
          .toggleRequestFavorite(_currentRequest.id!);

      // Check if widget is still mounted before showing toast
      if (mounted) {
        _showToast(
          newFavoriteStatus
              ? loc.translate('addedToFavorites')
              : loc.translate('removedFromFavorites'),
          newFavoriteStatus ? primaryColor : onSurfaceColor,
        );
      }
    } catch (e) {
      if (mounted) {
        _showToast(loc.translate('failedToUpdateFavorite'), errorColor);
      }
    }
  }

  String _getLocalizedStatusLabel() {
    final loc = AppLocalizations.of(context);
    final statusKey = _currentRequest.status.name;
    final translated = loc.translate(statusKey);

    if (translated.startsWith('** ')) {
      return _currentRequest.status.displayName;
    }

    return translated;
  }

  IconData _statusIcon(PropertyStatus status) {
    switch (status) {
      case PropertyStatus.available:
        return Icons.check_circle;
      case PropertyStatus.active:
        return Icons.sync;
      case PropertyStatus.sold:
        return Icons.attach_money;
      case PropertyStatus.rented:
        return Icons.vpn_key;
      case PropertyStatus.canceled:
        return Icons.cancel;
      case PropertyStatus.notAvailable:
        return Icons.remove_circle;
      case PropertyStatus.fulfilled:
        return Icons.task_alt;
      case PropertyStatus.closed:
        return Icons.highlight_off;
      case PropertyStatus.expired:
        return Icons.hourglass_bottom;
    }
  }

  String _getPropertyDisplayText() {
    final specific = _currentRequest.specificPropertyType.trim();
    final category = _currentRequest.propertyType?.trim();
    return [
      if (specific.isNotEmpty) _getLocalizedSpecificType(specific),
      if (category != null && category.isNotEmpty)
        _getLocalizedPropertyType(category),
    ].join(' - ');
  }

  String _getLocalizedPropertyType(String propertyType) {
    final loc = AppLocalizations.of(context);
    switch (propertyType.toLowerCase()) {
      case 'residential':
        return loc.translate('residential');
      case 'commercial':
        return loc.translate('commercial');
      case 'furnished':
        return loc.translate('furnished');
      default:
        return propertyType;
    }
  }

  String _getLocalizedSpecificType(String specificType) {
    final loc = AppLocalizations.of(context);
    // Convert to localization key format
    String key = _propertySubTypeKey(specificType);
    String localized = loc.translate(key);

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

  String _getLocationText() {
    final loc = AppLocalizations.of(context);
    List<String> locationParts = [];

    if (_currentRequest.selectedAreas.isNotEmpty) {
      // Use localized area name
      String firstArea = _currentRequest.selectedAreas.first;
      String areaKey = _areaLocalizationKey(firstArea);
      String localizedArea = loc.translate(areaKey);

      // If translation not found, use original
      if (localizedArea == '** $areaKey not found') {
        locationParts.add(firstArea);
      } else {
        locationParts.add(localizedArea);
      }
    }

    if (_currentRequest.selectedCity.isNotEmpty) {
      // Use localized city name
      String cityKey = _cityLocalizationKey(_currentRequest.selectedCity);
      String localizedCity = loc.translate(cityKey);

      // If translation not found, use original
      if (localizedCity == '** $cityKey not found') {
        locationParts.add(_currentRequest.selectedCity);
      } else {
        locationParts.add(localizedCity);
      }
    }

    return locationParts.join(', ');
  }

  bool _shouldShowRoomsAndBaths() {
    final allowedTypes = ['villa', 'apartment', 'studio'];
    return allowedTypes
        .contains(_currentRequest.specificPropertyType.toLowerCase());
  }

  // Action methods
  void _shareRequest() {
    // Built from the Request as this screen holds it, so sharing works offline
    // and shares this Request's own phone number (the one shown above).
    ShareOptionsDialog.show(
      context,
      source: PropertyShareSource.request(_currentRequest),
    );
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

  String _getLocalizedCityName(String city) {
    final loc = AppLocalizations.of(context);
    String cityKey = _cityLocalizationKey(city);
    String localizedCity = loc.translate(cityKey);

    // If translation not found, use original
    if (localizedCity == '** $cityKey not found') {
      return city;
    }
    return localizedCity;
  }

  String _getLocalizedAreasText(List<String> areas) {
    final loc = AppLocalizations.of(context);
    List<String> localizedAreas = areas.map((area) {
      String areaKey = _areaLocalizationKey(area);
      String localizedArea = loc.translate(areaKey);

      // If translation not found, use original
      if (localizedArea == '** $areaKey not found') {
        return area;
      }
      return localizedArea;
    }).toList();

    return localizedAreas.join(', ');
  }

  String _areaLocalizationKey(String area) {
    // Convert area name to localization key format
    switch (area.toLowerCase().replaceAll(' ', '').replaceAll('-', '')) {
      case "aljumeirah":
      case "jumeirah":
        return 'jumeirah';
      case "albarsha":
      case "barsha":
        return 'alBarsha';
      case "deira":
        return 'deira';
      case "karama":
        return 'karama';
      case "mirdif":
        return 'mirdif';
      case "discoverygardens":
        return 'discoveryGardens';
      case "burdubai":
        return 'burDubai';
      case "jvc":
      case "jumeirahvillagecircle":
        return 'jvc';
      case "downtowndubai":
        return 'downtownDubai';
      case "businessbay":
        return 'businessBay';
      case "alreemisland":
        return 'alReemIsland';
      case "alrahabeach":
        return 'alRahaBeach';
      case "khalifacity":
        return 'khalifaCity';
      case "mohammedbinzayedcity":
        return 'mohammedBinZayedCity';
      case "baniyas":
        return 'baniyas';
      case "alshamkha":
        return 'alShamkha';
      case "almuroor":
        return 'alMuroor';
      case "almaqtaa":
        return 'alMaqtaa';
      case "mussafah":
        return 'mussafah';
      case "albateen":
        return 'alBateen';
      case "alnahdasharjah":
      case "alnahda":
        return 'alNahdaSharjah';
      case "muwaileh":
        return 'muwaileh';
      case "almajaz":
        return 'alMajaz';
      case "alqasimia":
        return 'alQasimia';
      case "altaawun":
        return 'alTaawun';
      case "abushagara":
        return 'abuShagara';
      case "alyarmook":
        return 'alYarmook';
      case "albutina":
        return 'alButina';
      case "alkhan":
        return 'alKhan';
      case "alfalah":
        return 'alFalah';
      case "alnuaimia":
        return 'alNuaimia';
      case "alrashidiya":
        return 'alRashidiya';
      case "alrawda":
        return 'alRawda';
      case "alhelio":
        return 'alHelio';
      case "aljurf":
        return 'alJurf';
      case "alhamidiya":
        return 'alHamidiya';
      case "alzahra":
        return 'alZahra';
      case "almowaihat":
        return 'alMowaihat';
      case "emiratescity":
        return 'emiratesCity';
      case "ajmanindustrialarea":
        return 'ajmanIndustrialArea';
      case "aldhait":
        return 'alDhait';
      case "almairid":
        return 'alMairid';
      case "alqurm":
        return 'alQurm';
      case "alnakheel":
        return 'alNakheel';
      case "seihaluraibi":
        return 'seihAlUraibi';
      case "aljazeeraalhamra":
        return 'alJazeeraAlHamra';
      case "alrams":
        return 'alRams';
      case "aluraibi":
        return 'alUraibi';
      case "almamourah":
        return 'alMamourah';
      case "khuzam":
        return 'khuzam';
      case "alfaseel":
        return 'alFaseel';
      case "madhab":
        return 'madhab';
      case "murbah":
        return 'murbah';
      case "qalaaatalfujairah":
        return 'qalaatAlFujairah';
      case "dibbafujairah":
        return 'dibbaFujairah';
      case "algurfa":
        return 'alGurfa';
      case "sakamkam":
        return 'sakamkam';
      case "altawyeen":
        return 'alTawyeen';
      case "dadna":
        return 'dadna';
      case "albidya":
        return 'alBidya';
      case "alraafa":
        return 'alRaafa';
      case "alsalama":
        return 'alSalama';
      case "alramlah":
        return 'alRamlah';
      case "almurooruaq":
        return 'alMuroorUAQ';
      case "alkhoruaq":
        return 'alKhorUAQ';
      case "alhadarah":
        return 'alHadarah';
      case "alhaditha":
        return 'alHaditha';
      case "falajalmualla":
        return 'falajAlMualla';
      case "ummaquwaiindustrialarea":
        return 'ummaquwainIndustrialArea';
      case "alshabiya":
        return 'alShabiya';
      case "aljimi":
        return 'alJimi';
      case "alainindustrialarea":
        return 'alAinIndustrialArea';
      case "almuwaiji":
        return 'alMuwaiji';
      case "alameriya":
        return 'alAmeriya';
      case "alhili":
        return 'alHili';
      case "almarkhaniya":
        return 'alMarkhaniya';
      case "alyahar":
        return 'alYahar';
      case "alqattara":
        return 'alQattara';
      case "alkhabisi":
        return 'alKhabisi';
      case "zakhir":
        return 'zakhir';
      default:
        return area; // fallback to original
    }
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final loc = AppLocalizations.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    final result = await DetailsContactActions.call(phoneNumber,
        countryCode: _currentRequest.countryCode);
    if (!mounted || result == ContactLaunchResult.opened) return;
    _showToast(
        loc.translate(result == ContactLaunchResult.invalidPhone
            ? 'phoneNumberNotAvailable'
            : 'unableToMakePhoneCall'),
        errorColor);
  }

  Future<void> _copyPhone() async {
    final loc = AppLocalizations.of(context);
    if (_currentRequest.phoneNumber.isEmpty) {
      _showToast(loc.translate('noPhoneNumberToCopy'),
          Theme.of(context).colorScheme.error);
      return;
    }
    final dial = PhoneInputService.formatForDial(_currentRequest.phoneNumber);
    await Clipboard.setData(ClipboardData(text: dial));
    _showToast(loc.translate('phoneNumberCopied'),
        Theme.of(context).colorScheme.primary);
  }

  void _editRequest() async {
    // Navigate to edit request screen with data pre-filled
    final updatedRequest = await context.push(
      '/add-requested?mode=edit&id=${_currentRequest.id}',
      extra: _currentRequest, // Pass the current request data
    );

    // If an updated request was returned, update our state
    if (updatedRequest != null && updatedRequest is RequestModel) {
      setState(() {
        _currentRequest = updatedRequest;
      });
    }
  }

  // Show status selector dialog
  void _showStatusSelector() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: PropertyStatusSelector(
            currentStatus: _currentRequest.status,
            allowedStatuses: PropertyStatus.requestStatuses,
            onStatusSelected: _updateRequestStatus,
          ),
        ),
      ),
    );
  }

  // Update request status
  Future<void> _updateRequestStatus(PropertyStatus newStatus) async {
    if (_currentRequest.id == null) return;

    try {
      final updatedRequest = _currentRequest.copyWith(
        status: newStatus,
        updatedAt: DateTime.now(),
      );

      await _requestService.updateRequest(_currentRequest.id!, updatedRequest);
      if (!mounted) return;

      setState(() {
        _currentRequest = updatedRequest;
      });

      final loc = AppLocalizations.of(context);
      _showToast(
        '${loc.translate('request')} ${loc.translate('statusUpdatedTo')} ${newStatus.displayName}',
        Theme.of(context).colorScheme.primary,
      );
    } catch (_) {
      if (!mounted) return;
      final loc = AppLocalizations.of(context);
      _showToast(
        loc.translate('failedToUpdateStatus'),
        Theme.of(context).colorScheme.error,
      );
    }
  }

  // Show delete confirmation dialog
  Future<void> _showDeleteConfirmation() async {
    final loc = AppLocalizations.of(context);
    final confirmed = await showDeleteConfirmationDialog(
      context,
      title: loc.translate('deleteRequest'),
      message: loc.translate('deleteRequestConfirmationMessage'),
      itemIcon: Icons.search_rounded,
      itemLabel: _currentRequest.requestType == 'rent'
          ? loc.translate('rentRequest')
          : loc.translate('saleRequest'),
    );

    if (confirmed == true && _currentRequest.id != null) {
      await _deleteRequest();
    }
  }

  // Delete the request and navigate back
  Future<void> _deleteRequest() async {
    final loc = AppLocalizations.of(context);
    try {
      await _requestService.deleteRequest(_currentRequest.id!);

      if (mounted) {
        _showToast(loc.translate('requestDeletedSuccessfully'),
            const Color(0xFF4CAF50));
        // Navigate back to the previous screen
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        _showToast(
            loc.translate('failedToDeleteRequest'), const Color(0xFFC81E1E));
      }
    }
  }

  static void _showToast(String message, Color bgColor) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      timeInSecForIosWeb: 1,
      backgroundColor: bgColor,
      textColor: Colors.white,
    );
  }
}
