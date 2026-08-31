import 'package:flutter/material.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';
import 'package:share_plus/share_plus.dart';

class RequestShareOptionsDialog extends StatefulWidget {
  final RequestModel request;
  final String userPhoneNumber;

  const RequestShareOptionsDialog({
    super.key,
    required this.request,
    required this.userPhoneNumber,
  });

  @override
  State<RequestShareOptionsDialog> createState() =>
      _RequestShareOptionsDialogState();
}

class _RequestShareOptionsDialogState extends State<RequestShareOptionsDialog> {
  final Set<RequestShareOption> _selectedOptions = {};
  bool _selectAll = false;

  @override
  void initState() {
    super.initState();
    // Select all options by default (excluding media since requests don't have media)
    _selectedOptions.addAll(RequestShareOption.values.where(_hasDataForOption));
    _selectAll = true;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;
    final loc = AppLocalizations.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 600, maxWidth: 400),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.share_rounded,
                    color: colors.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loc.translate('shareRequest'),
                        style: texts.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        loc.translate('selectInfoToShare'),
                        style: texts.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon:
                      Icon(Icons.close_rounded, color: colors.onSurfaceVariant),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Select All Option
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colors.outline.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Transform.scale(
                    scale: 0.9,
                    child: Checkbox(
                      value: _selectAll,
                      onChanged: _toggleSelectAll,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    loc.translate('selectAll'),
                    style: texts.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: colors.onSurface,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Options List
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: RequestShareOption.values.map((option) {
                    return _buildOptionTile(option, colors, texts, loc);
                  }).toList(),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(
                          color: colors.outline.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      loc.translate('cancel'),
                      style: texts.bodyLarge?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed:
                        _selectedOptions.isNotEmpty ? _shareSelected : null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: colors.primary,
                      foregroundColor: colors.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.share_rounded, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          loc.translate('share'),
                          style: texts.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionTile(RequestShareOption option, ColorScheme colors,
      TextTheme texts, AppLocalizations loc) {
    final isSelected = _selectedOptions.contains(option);
    final hasData = _hasDataForOption(option);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: hasData ? () => _toggleOption(option) : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected
                  ? colors.primary.withValues(alpha: 0.08)
                  : hasData
                      ? Colors.transparent
                      : colors.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? colors.primary.withValues(alpha: 0.3)
                    : colors.outline.withValues(alpha: 0.1),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colors.primary.withValues(alpha: 0.15)
                        : hasData
                            ? colors.surfaceContainerHighest
                                .withValues(alpha: 0.8)
                            : colors.surfaceContainerHighest
                                .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    _getOptionIcon(option),
                    size: 16,
                    color: isSelected
                        ? colors.primary
                        : hasData
                            ? colors.onSurfaceVariant
                            : colors.onSurfaceVariant.withValues(alpha: 0.4),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getOptionTitle(option, loc),
                        style: texts.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: hasData
                              ? colors.onSurface
                              : colors.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                      ),
                      if (!hasData)
                        Text(
                          loc.translate('noDataAvailable'),
                          style: texts.bodySmall?.copyWith(
                            color:
                                colors.onSurfaceVariant.withValues(alpha: 0.6),
                          ),
                        ),
                    ],
                  ),
                ),
                if (hasData)
                  Transform.scale(
                    scale: 0.9,
                    child: Checkbox(
                      value: isSelected,
                      onChanged: (value) => _toggleOption(option),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  )
                else
                  Icon(
                    Icons.block_rounded,
                    size: 16,
                    color: colors.onSurfaceVariant.withValues(alpha: 0.4),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getOptionIcon(RequestShareOption option) {
    switch (option) {
      case RequestShareOption.basicInfo:
        return Icons.info_rounded;
      case RequestShareOption.pricing:
        return Icons.payments_rounded;
      case RequestShareOption.propertyDetails:
        return Icons.home_rounded;
      case RequestShareOption.locationDetails:
        return Icons.location_city_rounded;
      case RequestShareOption.contact:
        return Icons.phone_rounded;
      case RequestShareOption.notes:
        return Icons.note_rounded;
    }
  }

  String _getOptionTitle(RequestShareOption option, AppLocalizations loc) {
    switch (option) {
      case RequestShareOption.basicInfo:
        return loc.translate('basicInformation');
      case RequestShareOption.pricing:
        return loc.translate('pricing');
      case RequestShareOption.propertyDetails:
        return loc.translate('propertyDetails');
      case RequestShareOption.locationDetails:
        return loc.translate('locationDetails');
      case RequestShareOption.contact:
        return loc.translate('contactInfo');
      case RequestShareOption.notes:
        return loc.translate('notes');
    }
  }

  bool _hasDataForOption(RequestShareOption option) {
    switch (option) {
      case RequestShareOption.basicInfo:
        return true; // Always has basic info
      case RequestShareOption.pricing:
        return widget.request.minPrice.isNotEmpty ||
            widget.request.maxPrice.isNotEmpty;
      case RequestShareOption.propertyDetails:
        return widget.request.specificPropertyType.isNotEmpty ||
            widget.request.rooms > 0 ||
            widget.request.bathrooms > 0;
      case RequestShareOption.locationDetails:
        return widget.request.selectedAreas.isNotEmpty ||
            widget.request.selectedCity.isNotEmpty;
      case RequestShareOption.contact:
        return widget.userPhoneNumber.isNotEmpty;
      case RequestShareOption.notes:
        return widget.request.notes.isNotEmpty;
    }
  }

  void _toggleSelectAll(bool? value) {
    setState(() {
      _selectAll = value ?? false;
      if (_selectAll) {
        _selectedOptions.clear();
        _selectedOptions
            .addAll(RequestShareOption.values.where(_hasDataForOption));
      } else {
        _selectedOptions.clear();
      }
    });
  }

  void _toggleOption(RequestShareOption option) {
    if (!_hasDataForOption(option)) return;

    setState(() {
      if (_selectedOptions.contains(option)) {
        _selectedOptions.remove(option);
      } else {
        _selectedOptions.add(option);
      }

      // Update select all state
      final availableOptions =
          RequestShareOption.values.where(_hasDataForOption).toSet();
      _selectAll = _selectedOptions.containsAll(availableOptions);
    });
  }

  Future<void> _shareSelected() async {
    if (_selectedOptions.isEmpty) return;

    final shareText = _generateShareText();
    final loc = AppLocalizations.of(context);

    Navigator.of(context).pop();

    // Share text only (requests don't have media)
    await SharePlus.instance.share(
      ShareParams(
        text: shareText,
        subject: loc.translate('requestDetails'),
      ),
    );
  }

  String _generateShareText() {
    final loc = AppLocalizations.of(context);
    final buffer = StringBuffer();

    // Header
    buffer.writeln('${loc.translate('requestDetails')}');
    buffer.writeln('${'=' * 24}');
    buffer.writeln();

    // Property Details (combining basic info and property details)
    if (_selectedOptions.contains(RequestShareOption.basicInfo) ||
        _selectedOptions.contains(RequestShareOption.propertyDetails)) {
      buffer.writeln('🏡 ${loc.translate('propertyDetails')}:');

      // Request Type
      if (_selectedOptions.contains(RequestShareOption.basicInfo)) {
        buffer.writeln(
            '• ${loc.translate('requestType')}: ${_getLocalizedRequestType()}');
      }

      // Property Type (show both if available: "Commercial - Villa")
      if (_selectedOptions.contains(RequestShareOption.basicInfo) &&
          widget.request.specificPropertyType.isNotEmpty) {
        String propertyTypeText = '';
        if (widget.request.propertyType != null &&
            widget.request.propertyType!.isNotEmpty) {
          // Localize the main property type (residential, commercial, etc.)
          propertyTypeText = '${_getLocalizedMainPropertyType()} - ';
        }
        propertyTypeText += _getLocalizedPropertyType();
        buffer.writeln('• ${loc.translate('propertyType')}: $propertyTypeText');
      }

      // Rooms and Bathrooms
      if (_selectedOptions.contains(RequestShareOption.propertyDetails)) {
        if (widget.request.rooms > 0) {
          buffer
              .writeln('• ${loc.translate('rooms')}: ${widget.request.rooms}');
        }
        if (widget.request.bathrooms > 0) {
          buffer.writeln(
              '• ${loc.translate('bathrooms')}: ${widget.request.bathrooms}');
        }
      }
      buffer.writeln();
    }

    // Square Footage
    if (_selectedOptions.contains(RequestShareOption.propertyDetails) &&
        widget.request.squareFootage.isNotEmpty) {
      buffer.writeln('📐 ${loc.translate('squareFootage')}');
      buffer.writeln(
          '• ${loc.translate('sqft')}: ${widget.request.squareFootage}');
      buffer.writeln();
    }

    // Pricing (show min price as requested)
    if (_selectedOptions.contains(RequestShareOption.pricing) &&
        _hasDataForOption(RequestShareOption.pricing)) {
      // For requests, prioritize min price
      if (widget.request.minPrice.isNotEmpty) {
        buffer.writeln(
            '• ${loc.translate('price')}: ${widget.request.minPrice} 💰');
      } else if (widget.request.maxPrice.isNotEmpty) {
        buffer.writeln(
            '• ${loc.translate('price')}: ${widget.request.maxPrice} 💰');
      }
      buffer.writeln();
    }

    // Location Details (City and Areas as requested)
    if (_selectedOptions.contains(RequestShareOption.locationDetails)) {
      buffer.writeln('📍 ${loc.translate('locationDetails')}:');

      // City
      if (widget.request.selectedCity.isNotEmpty) {
        buffer.writeln('• ${loc.translate('city')}: ${_getLocalizedCity()}');
      }

      // Areas
      if (widget.request.selectedAreas.isNotEmpty) {
        buffer.writeln('• ${loc.translate('areas')}: ${_getLocalizedAreas()}');
      }
      buffer.writeln();
    }

    // Contact Information (use current user's phone number)
    if (_selectedOptions.contains(RequestShareOption.contact) &&
        widget.userPhoneNumber.isNotEmpty) {
      buffer.writeln('📞 ${loc.translate('contactInfo')}:');
      buffer.writeln('• ${loc.translate('phone')}: ${widget.userPhoneNumber}');
      buffer.writeln();
    }

    // Notes
    if (_selectedOptions.contains(RequestShareOption.notes) &&
        _hasDataForOption(RequestShareOption.notes)) {
      buffer.writeln('📝 ${loc.translate('notes')}:');
      buffer.writeln(widget.request.notes);
      buffer.writeln();
    }

    // Footer
    buffer.writeln('${'=' * 24}');
    buffer.writeln('📱 ${loc.translate('sharedByBrokerWallet')}');

    return buffer.toString();
  }

  String _getLocalizedRequestType() {
    final loc = AppLocalizations.of(context);
    return widget.request.requestType == 'rent'
        ? loc.translate('rentRequest')
        : loc.translate('saleRequest');
  }

  String _getLocalizedMainPropertyType() {
    final loc = AppLocalizations.of(context);
    final mainPropertyType =
        widget.request.propertyType?.toLowerCase().trim() ?? '';

    if (mainPropertyType.isEmpty) return '';

    // Try to translate common property type categories
    String translationKey = mainPropertyType;

    // Handle common property type categories
    switch (mainPropertyType) {
      case 'residential':
        translationKey = 'residential';
        break;
      case 'commercial':
        translationKey = 'commercial';
        break;
      case 'furnished':
        translationKey = 'furnished';
        break;
      default:
        translationKey = mainPropertyType;
    }

    final translated = loc.translate(translationKey);

    // If translation is the same as key, return original with first letter capitalized
    if (translated == translationKey) {
      return mainPropertyType[0].toUpperCase() + mainPropertyType.substring(1);
    }

    return translated;
  }

  String _getLocalizedPropertyType() {
    final loc = AppLocalizations.of(context);
    final type = widget.request.specificPropertyType;

    if (type.isEmpty) return '';

    // Use the SAME conversion logic as _propertySubTypeKey() in add_offers_view.dart
    final translationKey = _propertySubTypeKey(type);

    final translated = loc.translate(translationKey);

    // If translation is the same as key, return original (capitalized)
    return translated == translationKey ? type : translated;
  }

  // Convert property type to translation key - SAME logic as add_offers_view.dart
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
        return type.toLowerCase().replaceAll(' ', '');
    }
  }

  String _getLocalizedCity() {
    final loc = AppLocalizations.of(context);
    final cityKey = _cityLocalizationKey(widget.request.selectedCity);
    final translated = loc.translate(cityKey);

    // If translation not found, use original
    return translated == '** $cityKey not found'
        ? widget.request.selectedCity
        : translated;
  }

  String _cityLocalizationKey(String city) {
    switch (city.toLowerCase().replaceAll(' ', '')) {
      case "dubai":
        return "dubai";
      case "abudhabi":
        return "abuDhabi";
      case "sharjah":
        return "sharjah";
      case "ajman":
        return "ajman";
      case "ummalquwain":
      case "uaq":
        return "ummAlQuwain";
      case "rasalkhaimah":
      case "rak":
        return "rasAlKhaimah";
      case "fujairah":
        return "fujairah";
      case "alain":
        return "alAin";
      default:
        return city.toLowerCase().replaceAll(' ', '');
    }
  }

  String _getLocalizedAreas() {
    final loc = AppLocalizations.of(context);
    List<String> localizedAreas = widget.request.selectedAreas.map((area) {
      final areaKey = _areaLocalizationKey(area);
      final localizedArea = loc.translate(areaKey);

      // If translation not found, use original
      return localizedArea == '** $areaKey not found' ? area : localizedArea;
    }).toList();

    return localizedAreas.join(', ');
  }

  String _areaLocalizationKey(String area) {
    // Convert area name to localization key format
    switch (area.toLowerCase().replaceAll(' ', '').replaceAll('-', '')) {
      case "jumeirahbeachresidence":
      case "jbr":
        return "jumeirahBeachResidence";
      case "dubaimarina":
        return "dubaiMarina";
      case "downtown":
      case "downtowndubai":
        return "downtown";
      case "businessbay":
        return "businessBay";
      case "dubailand":
        return "dubailand";
      case "jumeirahvillagecircle":
      case "jvc":
        return "jumeirahVillageCircle";
      case "dubaisouthcity":
        return "dubaiSouthCity";
      case "dubaiinvestmentpark":
      case "dip":
        return "dubaiInvestmentPark";
      case "dubaisportscity":
        return "dubaiSportsCity";
      case "motorcity":
        return "motorCity";
      case "arabiangolfcourse":
        return "arabianGolfCourse";
      case "thegreens":
        return "theGreens";
      case "emirates":
        return "emirates";
      case "theviews":
        return "theViews";
      case "springsofarabia":
        return "springsOfArabia";
      case "meadorsofarabia":
        return "meadowsOfArabia";
      case "lakesarabia":
        return "lakesArabia";
      case "discoverygardens":
        return "discoveryGardens";
      case "thegreenscommunity":
        return "theGreensCommunity";
      default:
        return area.toLowerCase().replaceAll(' ', '').replaceAll('-', '');
    }
  }
}

enum RequestShareOption {
  basicInfo,
  pricing,
  propertyDetails,
  locationDetails,
  contact,
  notes,
}
