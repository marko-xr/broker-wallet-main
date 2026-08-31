import 'package:flutter/material.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class ShareOptionsDialog extends StatefulWidget {
  final OfferModel offer;
  final String userPhoneNumber;

  const ShareOptionsDialog({
    super.key,
    required this.offer,
    required this.userPhoneNumber,
  });

  @override
  State<ShareOptionsDialog> createState() => _ShareOptionsDialogState();
}

class _ShareOptionsDialogState extends State<ShareOptionsDialog> {
  final Set<ShareOption> _selectedOptions = {};
  bool _selectAll = false;

  @override
  void initState() {
    super.initState();
    // Select all options by default
    _selectedOptions.addAll(ShareOption.values);
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
                    borderRadius: BorderRadius.circular(8),
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
                        loc.translate('shareOffer'),
                        style: texts.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colors.onSurface,
                        ),
                      ),
                      Text(
                        loc.translate('selectDataToShare'),
                        style: texts.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(
                    Icons.close_rounded,
                    color: colors.onSurfaceVariant,
                  ),
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
                    scale: 1.1,
                    child: Checkbox(
                      value: _selectAll,
                      onChanged: _toggleSelectAll,
                      activeColor: colors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      loc.translate('selectAll'),
                      style: texts.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
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
                  children: ShareOption.values.map((option) {
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
                      side: BorderSide(color: colors.outline),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      loc.translate('cancel'),
                      style: texts.titleSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed:
                        _selectedOptions.isNotEmpty ? _shareSelected : null,
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: Text(
                      loc.translate('shareSelected'),
                      style: texts.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: colors.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
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

  Widget _buildOptionTile(ShareOption option, ColorScheme colors,
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
                    color: hasData
                        ? (isSelected
                            ? colors.primary
                            : colors.surfaceContainerHighest)
                        : colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    _getOptionIcon(option),
                    size: 16,
                    color: hasData
                        ? (isSelected
                            ? colors.onPrimary
                            : colors.onSurfaceVariant)
                        : colors.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getOptionTitle(option, loc),
                        style: texts.titleSmall?.copyWith(
                          color: hasData
                              ? colors.onSurface
                              : colors.onSurfaceVariant.withValues(alpha: 0.6),
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                      if (!hasData) ...[
                        const SizedBox(height: 2),
                        Text(
                          loc.translate('noDataAvailable'),
                          style: texts.bodySmall?.copyWith(
                            color:
                                colors.onSurfaceVariant.withValues(alpha: 0.6),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (hasData)
                  Transform.scale(
                    scale: 0.9,
                    child: Checkbox(
                      value: isSelected,
                      onChanged: (_) => _toggleOption(option),
                      activeColor: colors.primary,
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

  IconData _getOptionIcon(ShareOption option) {
    switch (option) {
      case ShareOption.basicInfo:
        return Icons.info_rounded;
      case ShareOption.pricing:
        return Icons.payments_rounded;
      case ShareOption.propertyDetails:
        return Icons.home_rounded;
      case ShareOption.locationDetails:
        return Icons.location_city_rounded;
      case ShareOption.map:
        return Icons.map_rounded;
      case ShareOption.contact:
        return Icons.phone_rounded;
      case ShareOption.notes:
        return Icons.note_rounded;
      case ShareOption.media:
        return Icons.photo_library_rounded;
    }
  }

  String _getOptionTitle(ShareOption option, AppLocalizations loc) {
    switch (option) {
      case ShareOption.basicInfo:
        return loc.translate('basicInformation');
      case ShareOption.pricing:
        return loc.translate('pricing');
      case ShareOption.propertyDetails:
        return loc.translate('propertyDetails');
      case ShareOption.locationDetails:
        return loc.translate('locationDetails');
      case ShareOption.map:
        return loc.translate('mapLocation');
      case ShareOption.contact:
        return loc.translate('contactInfo');
      case ShareOption.notes:
        return loc.translate('notes');
      case ShareOption.media:
        return loc.translate('mediaFiles');
    }
  }

  bool _hasDataForOption(ShareOption option) {
    switch (option) {
      case ShareOption.basicInfo:
        return true; // Always has basic info
      case ShareOption.pricing:
        return widget.offer.minPrice.isNotEmpty ||
            widget.offer.maxPrice.isNotEmpty;
      case ShareOption.propertyDetails:
        return widget.offer.specificPropertyType.isNotEmpty ||
            widget.offer.rooms > 0 ||
            widget.offer.bathrooms > 0;
      case ShareOption.locationDetails:
        return widget.offer.selectedAreas.isNotEmpty ||
            widget.offer.selectedCity.isNotEmpty ||
            widget.offer.location.isNotEmpty;
      case ShareOption.map:
        return widget.offer.pickUpLatitude != null &&
                widget.offer.pickUpLongitude != null ||
            widget.offer.pickUpLocation.isNotEmpty ||
            widget.offer.pickUpAddress.isNotEmpty;
      case ShareOption.contact:
        return widget.userPhoneNumber.isNotEmpty;
      case ShareOption.notes:
        return widget.offer.notes.isNotEmpty;
      case ShareOption.media:
        return widget.offer.mediaUrls.isNotEmpty;
    }
  }

  void _toggleSelectAll(bool? value) {
    setState(() {
      _selectAll = value ?? false;
      if (_selectAll) {
        _selectedOptions.clear();
        _selectedOptions.addAll(ShareOption.values.where(_hasDataForOption));
      } else {
        _selectedOptions.clear();
      }
    });
  }

  void _toggleOption(ShareOption option) {
    if (!_hasDataForOption(option)) return;

    setState(() {
      if (_selectedOptions.contains(option)) {
        _selectedOptions.remove(option);
      } else {
        _selectedOptions.add(option);
      }

      // Update select all state
      final availableOptions =
          ShareOption.values.where(_hasDataForOption).toSet();
      _selectAll = _selectedOptions.containsAll(availableOptions);
    });
  }

  Future<void> _shareSelected() async {
    if (_selectedOptions.isEmpty) return;

    final shareText = _generateShareText();
    final loc = AppLocalizations.of(context);

    // Check if media is selected and available
    final shouldShareImage = _selectedOptions.contains(ShareOption.media) &&
        widget.offer.mediaUrls.isNotEmpty;

    Navigator.of(context).pop();

    if (shouldShareImage) {
      try {
        // Download the first image
        final imageUrl = widget.offer.mediaUrls.first;
        final response = await http.get(Uri.parse(imageUrl));

        if (response.statusCode == 200) {
          // Get temporary directory
          final tempDir = await getTemporaryDirectory();

          // Extract file extension from URL or default to jpg
          String extension = 'jpg';
          final uri = Uri.parse(imageUrl);
          final pathSegments = uri.pathSegments;
          if (pathSegments.isNotEmpty) {
            final lastSegment = pathSegments.last;
            if (lastSegment.contains('.')) {
              extension = lastSegment.split('.').last.split('?').first;
            }
          }

          // Create a temporary file
          final fileName =
              'offer_image_${DateTime.now().millisecondsSinceEpoch}.$extension';
          final filePath = '${tempDir.path}/$fileName';
          final file = File(filePath);
          await file.writeAsBytes(response.bodyBytes);

          // Share image with text
          await SharePlus.instance.share(
            ShareParams(
              files: [XFile(filePath)],
              text: shareText,
              subject: loc.translate('offerDetails'),
            ),
          );
          return;
        }
      } catch (e) {
        debugPrint('Error sharing image: $e');
        // Fall back to text-only sharing if image fails
      }
    }

    // Share text only (if no image selected or image download failed)
    await SharePlus.instance.share(
      ShareParams(
        text: shareText,
        subject: loc.translate('offerDetails'),
      ),
    );
  }

  String _generateShareText() {
    final loc = AppLocalizations.of(context);
    final buffer = StringBuffer();

    // Header
    buffer.writeln('${loc.translate('offerDetails')}');
    buffer.writeln('${'=' * 24}');
    buffer.writeln();

    // Property Details (combining basic info and property details)
    if (_selectedOptions.contains(ShareOption.basicInfo) ||
        _selectedOptions.contains(ShareOption.propertyDetails)) {
      buffer.writeln('🏡 ${loc.translate('propertyDetails')}:');

      // Offer Type
      if (_selectedOptions.contains(ShareOption.basicInfo)) {
        buffer.writeln(
            '• ${loc.translate('offerType')}: ${_getLocalizedOfferType()}');
      }

      // Property Type (show both if available: "Commercial - Villa")
      if (_selectedOptions.contains(ShareOption.basicInfo) &&
          widget.offer.specificPropertyType.isNotEmpty) {
        String propertyTypeText = '';
        if (widget.offer.propertyType != null &&
            widget.offer.propertyType!.isNotEmpty) {
          // Localize the main property type (residential, commercial, etc.)
          propertyTypeText = '${_getLocalizedMainPropertyType()} - ';
        }
        propertyTypeText += _getLocalizedPropertyType();
        buffer.writeln('• ${loc.translate('propertyType')}: $propertyTypeText');
      }

      // Rooms and Bathrooms
      if (_selectedOptions.contains(ShareOption.propertyDetails)) {
        if (widget.offer.rooms > 0) {
          buffer.writeln('• ${loc.translate('rooms')}: ${widget.offer.rooms}');
        }
        if (widget.offer.bathrooms > 0) {
          buffer.writeln(
              '• ${loc.translate('bathrooms')}: ${widget.offer.bathrooms}');
        }
      }
      buffer.writeln();
    }

    // Square Footage
    if (_selectedOptions.contains(ShareOption.propertyDetails) &&
        widget.offer.squareFootage.isNotEmpty) {
      buffer.writeln('📐 ${loc.translate('squareFootage')}');
      buffer
          .writeln('• ${loc.translate('sqft')}: ${widget.offer.squareFootage}');
      buffer.writeln();
    }

    // Pricing (only show max price if both are provided, otherwise show what's available)
    if (_selectedOptions.contains(ShareOption.pricing) &&
        _hasDataForOption(ShareOption.pricing)) {
      // If both prices exist, only show max price
      if (widget.offer.maxPrice.isNotEmpty) {
        buffer
            .writeln('💰 ${loc.translate('price')}: ${widget.offer.maxPrice}');
      } else if (widget.offer.minPrice.isNotEmpty) {
        buffer
            .writeln('💰 ${loc.translate('price')}: ${widget.offer.minPrice}');
      }
      buffer.writeln();
    }

    // Location Details (City and Map Link only)
    if (_selectedOptions.contains(ShareOption.locationDetails) ||
        _selectedOptions.contains(ShareOption.map)) {
      buffer.writeln('📍 ${loc.translate('locationDetails')}:');

      // City
      if (_selectedOptions.contains(ShareOption.locationDetails) &&
          widget.offer.selectedCity.isNotEmpty) {
        buffer.writeln('• ${loc.translate('city')}: ${_getLocalizedCity()}');
      }

      // Map Link
      if (_selectedOptions.contains(ShareOption.map) &&
          widget.offer.pickUpLatitude != null &&
          widget.offer.pickUpLongitude != null) {
        final googleMapsLink =
            'https://maps.google.com/?q=${widget.offer.pickUpLatitude},${widget.offer.pickUpLongitude}';
        buffer.writeln('• ${loc.translate('mapLink')}: $googleMapsLink');
      }
      buffer.writeln();
    }

    // Contact Information (use current user's phone number)
    if (_selectedOptions.contains(ShareOption.contact) &&
        widget.userPhoneNumber.isNotEmpty) {
      buffer.writeln('📞 ${loc.translate('contactInfo')}:');
      buffer.writeln('• ${loc.translate('phone')}: ${widget.userPhoneNumber}');
      buffer.writeln();
    }

    // Notes
    if (_selectedOptions.contains(ShareOption.notes) &&
        _hasDataForOption(ShareOption.notes)) {
      buffer.writeln('📝 ${loc.translate('notes')}:');
      buffer.writeln(widget.offer.notes);
      buffer.writeln();
    }

    // Media - Image will be shared as file attachment, not in text
    // No need to include URL in the text

    // Footer
    buffer.writeln('${'=' * 24}');
    buffer.writeln('📱 ${loc.translate('sharedByBrokerWallet')}');

    return buffer.toString();
  }

  String _getLocalizedOfferType() {
    final loc = AppLocalizations.of(context);
    return widget.offer.offerType == 'rent'
        ? loc.translate('rentOffer')
        : loc.translate('saleOffer');
  }

  String _getLocalizedMainPropertyType() {
    final loc = AppLocalizations.of(context);
    final mainPropertyType =
        widget.offer.propertyType?.toLowerCase().trim() ?? '';

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
    final type = widget.offer.specificPropertyType;

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
    final city = widget.offer.selectedCity.toLowerCase();

    // Try to translate the city
    final translated = loc.translate(city);

    // If translation is the same as key, return original
    return translated == city ? widget.offer.selectedCity : translated;
  }
}

enum ShareOption {
  basicInfo,
  pricing,
  propertyDetails,
  locationDetails,
  map,
  contact,
  notes,
  media,
}
