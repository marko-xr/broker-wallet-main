import 'package:broker_wallet/src/Views/Widgets/favorite_button.dart';
import 'package:broker_wallet/src/services/optimistic_favorites_service.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/utils/map_coordinates.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offices_model.dart';
import 'package:broker_wallet/src/services/ScreenServices/office_service.dart';
import 'package:broker_wallet/src/services/related_items_service.dart';
import 'package:broker_wallet/src/widgets/auto_scrolling_related_items_carousel.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import 'package:broker_wallet/src/services/phone_input_service.dart';
import 'package:broker_wallet/src/services/details_contact_actions.dart';
import 'package:broker_wallet/src/services/share/share_sources.dart';
import 'package:broker_wallet/src/views/Widgets/share_options_dialog.dart';

import 'widgets/details_page.dart';
import 'widgets/details_section.dart';
import 'package:broker_wallet/src/views/Widgets/delete_confirmation_dialog.dart';
import 'package:broker_wallet/src/views/Widgets/field_icons.dart';

class OfficesDetailsView extends StatefulWidget {
  final OfficeModel office;
  final RelatedItemsService? relatedItemsService;
  final Widget? mapPreview;

  const OfficesDetailsView({
    super.key,
    required this.office,
    this.relatedItemsService,
    this.mapPreview,
  });

  @override
  State<OfficesDetailsView> createState() => _OfficesDetailsViewState();
}

class _OfficesDetailsViewState extends State<OfficesDetailsView>
    with TickerProviderStateMixin {
  late AnimationController _mainAnimationController;
  late AnimationController _fabAnimationController;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _fabAnimation;

  GoogleMapController? _mapController;
  final ScrollController _scrollController = ScrollController();

  // Services
  final OfficeService _officeService = OfficeService();
  late final RelatedItemsService _relatedItemsService =
      widget.relatedItemsService ?? RelatedItemsService();
  String? _relatedPhone;
  Stream<List<OfferModel>>? _relatedOffers;
  Stream<List<RequestModel>>? _relatedRequests;

  // Favorite state - now managed by OptimisticFavoritesService
  late OptimisticFavoritesService _optimisticFavoritesService;

  // Track current office data
  late OfficeModel _currentOffice;

  // Performance optimization: Cache expensive widgets
  Widget? _cachedMapWidget;

  @override
  void initState() {
    super.initState();
    _currentOffice = widget.office;
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
    final phone = _currentOffice.phoneNumber;
    final canContact = DetailsContactActions.normalizePhone(phone,
            countryCode: _currentOffice.countryCode) !=
        null;
    return DetailsPage(
      title: loc.translate('officeDetails'),
      favorite: Consumer<OptimisticFavoritesService>(builder: _buildFavorite),
      onShare: _shareOffice,
      onEdit: _editOffice,
      onDelete: _showDeleteConfirmation,
      deleteLabel: loc.translate('deleteOffice'),
      onWhatsApp: !canContact ? null : () => _openWhatsApp(phone),
      onCall: !canContact ? null : () => _makePhoneCall(phone),
      scrollController: _scrollController,
      fade: _fadeAnimation,
      slide: _slideAnimation,
      contactFade: _fabAnimation,
      content: _buildCompactContent,
    );
  }

  Widget _buildFavorite(BuildContext context,
      OptimisticFavoritesService favorites, Widget? child) {
    final id = _currentOffice.id;
    if (id == null || id.isEmpty) {
      return const Icon(Icons.favorite_border, size: 18);
    }
    return OptimizedFavoriteButton(
      size: 18,
      padding: const EdgeInsets.all((kMinInteractiveDimension - 18) / 2),
      isFavorite: favorites.isOfficeFavorite(id),
      isLoading: favorites.isOfficeLoading(id),
      onToggle: _toggleFavorite,
    );
  }

  Widget _buildCompactContent(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final name = _currentOffice.officeName.trim();
    final secondary = _currentOffice.officeLocation.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DetailsSummary(
          title: name.isEmpty ? loc.translate('officeNameNotSpecified') : name,
          titleLabel: loc.translate('officeName'),
          titleMissing: name.isEmpty,
          icon: FieldIcons.location,
          subtitle: secondary.isEmpty ? null : secondary,
          subtitleLabel: loc.translate('officeLocation'),
        ),
        const SizedBox(height: DetailsSection.spacing),
        DetailsFields(
          title: loc.translate('basicInformation'),
          rows: [
            DetailsField(
              icon: FieldIcons.manager,
              label: loc.translate('managerName'),
              isMissing: _currentOffice.managerName.trim().isEmpty,
              value: _currentOffice.managerName.trim().isNotEmpty
                  ? _currentOffice.managerName
                  : loc.translate('managerNotSpecified'),
            ),
            if (secondary.isEmpty)
              DetailsField(
                icon: FieldIcons.location,
                label: loc.translate('officeLocation'),
                value: loc.translate('officeLocationNotSpecified'),
                isMissing: true,
              ),
            DetailsField(
              icon: FieldIcons.phone,
              label: loc.translate('phoneNumber'),
              isMissing: _currentOffice.phoneNumber.trim().isEmpty,
              value: _currentOffice.phoneNumber.trim().isNotEmpty
                  ? PhoneInputService.formatForDisplay(
                      _currentOffice.phoneNumber)
                  : loc.translate('phoneNotAdded'),
              onCopy: _currentOffice.phoneNumber.trim().isNotEmpty
                  ? _copyPhone
                  : null,
            ),
            ...DetailsDates.fields(context,
                createdAt: _currentOffice.createdAt,
                updatedAt: _currentOffice.updatedAt),
          ],
        ),
        if (_currentOffice.notes.isNotEmpty) ...[
          const SizedBox(height: DetailsSection.spacing),
          DetailsNotes(notes: _currentOffice.notes),
        ],
        const SizedBox(height: DetailsSection.spacing),
        _buildCompactLocationCard(context),
        _buildRelatedItemsCarousel(context),
      ],
    );
  }

  Widget _buildRelatedItemsCarousel(BuildContext context) {
    final phone = _currentOffice.phoneNumber;
    if (_relatedPhone != phone) {
      _relatedPhone = phone;
      _relatedOffers =
          phone.isEmpty ? null : _relatedItemsService.getRelatedOffers(phone);
      _relatedRequests =
          phone.isEmpty ? null : _relatedItemsService.getRelatedRequests(phone);
    }
    if (phone.isEmpty) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<List<OfferModel>>(
      stream: _relatedOffers,
      builder: (context, offersSnapshot) {
        return StreamBuilder<List<RequestModel>>(
          stream: _relatedRequests,
          builder: (context, requestsSnapshot) {
            final offers = offersSnapshot.data ?? [];
            final requests = requestsSnapshot.data ?? [];

            // Only show if there are related items
            if (offers.isEmpty && requests.isEmpty) {
              return const SizedBox.shrink();
            }

            return AutoScrollingRelatedItemsCarousel(
              offers: offers,
              requests: requests,
            );
          },
        );
      },
    );
  }

  Widget _buildCompactLocationCard(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final hasMap = MapCoordinates.isValid(
        _currentOffice.pickUpLatitude, _currentOffice.pickUpLongitude);
    // Null, not a fallback string: when there's no address text, DetailsMap's
    // own "map not available" message already says so — showing a second,
    // separately-worded "no address" line next to it would just repeat it.
    final address = _currentOffice.pickUpAddress.trim().isNotEmpty
        ? _currentOffice.pickUpAddress
        : (_currentOffice.pickUpLocation.trim().isNotEmpty
            ? _currentOffice.pickUpLocation
            : null);
    return DetailsMap(
      title: loc.translate(hasMap ? 'officeLocationOnMap' : 'officeLocation'),
      address: address,
      onOpen: hasMap ? _openInMaps : null,
      preview: hasMap ? _buildCachedMiniMap(context) : null,
    );
  }

  Widget _buildCachedMiniMap(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    _cachedMapWidget ??= GestureDetector(
      onTap: _openInMaps,
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colors.outline.withValues(alpha: 0.2),
          ),
          boxShadow: [
            BoxShadow(
              color: colors.shadow.withValues(alpha: 0.1),
              blurRadius: 8,
              spreadRadius: 0,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: widget.mapPreview ??
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: LatLng(
                    _currentOffice.pickUpLatitude!,
                    _currentOffice.pickUpLongitude!,
                  ),
                  zoom: 15,
                ),
                markers: {
                  Marker(
                    markerId: const MarkerId('pickup_location'),
                    position: LatLng(
                      _currentOffice.pickUpLatitude!,
                      _currentOffice.pickUpLongitude!,
                    ),
                    infoWindow: InfoWindow(
                      title: _currentOffice.pickUpLocation,
                    ),
                    onTap: () => _openInMaps(),
                  ),
                },
                onMapCreated: (GoogleMapController controller) {
                  _mapController = controller;
                },
                onTap: (LatLng latLng) => _openInMaps(),
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                gestureRecognizers: const <Factory<
                    OneSequenceGestureRecognizer>>{},
              ),
        ),
      ),
    );

    return _cachedMapWidget!;
  }

  Future<void> _openWhatsApp(String phoneNumber) async {
    final loc = AppLocalizations.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    final result = await DetailsContactActions.whatsApp(phoneNumber,
        countryCode: _currentOffice.countryCode);
    if (!mounted || result == ContactLaunchResult.opened) return;
    _showToast(
        loc.translate(result == ContactLaunchResult.invalidPhone
            ? 'phoneNumberNotAvailable'
            : 'couldNotOpenWhatsApp'),
        errorColor);
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final loc = AppLocalizations.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    final result = await DetailsContactActions.call(phoneNumber,
        countryCode: _currentOffice.countryCode);
    if (!mounted || result == ContactLaunchResult.opened) return;
    _showToast(
        loc.translate(result == ContactLaunchResult.invalidPhone
            ? 'phoneNumberNotAvailable'
            : 'unableToMakePhoneCall'),
        errorColor);
  }

  Future<void> _toggleFavorite() async {
    if (_currentOffice.id == null) return;

    final loc = AppLocalizations.of(context);
    // Capture theme colors before async operation
    final primaryColor = Theme.of(context).colorScheme.primary;
    final onSurfaceColor = Theme.of(context).colorScheme.onSurface;
    final errorColor = Theme.of(context).colorScheme.error;

    try {
      final newFavoriteStatus = await _optimisticFavoritesService
          .toggleOfficeFavorite(_currentOffice.id!);

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
        _showToast(loc.translate('failedToUpdateFavoriteStatus'), errorColor);
      }
    }
  }

  void _shareOffice() {
    ShareOptionsDialog.show(
      context,
      source: OfficeShareSource(_currentOffice),
    );
  }

  Future<void> _copyPhone() async {
    final loc = AppLocalizations.of(context);

    if (_currentOffice.phoneNumber.isEmpty) {
      _showToast(loc.translate('noPhoneNumberToCopy'),
          Theme.of(context).colorScheme.error);
      return;
    }
    final dial = PhoneInputService.formatForDial(_currentOffice.phoneNumber);
    await Clipboard.setData(ClipboardData(text: dial));
    _showToast(loc.translate('phoneNumberCopiedToClipboard'),
        Theme.of(context).colorScheme.primary);
  }

  void _openInMaps() async {
    final lat = _currentOffice.pickUpLatitude;
    final lng = _currentOffice.pickUpLongitude;
    if (MapCoordinates.isValid(lat, lng)) {
      final uri = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=$lat,$lng');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    }
  }

  void _editOffice() async {
    final updatedOffice = await context.push(
      '/add-offices?mode=edit&id=${_currentOffice.id}',
      extra: _currentOffice, // Pass the current office data
    );

    // If an updated office was returned, update our state
    if (updatedOffice != null && updatedOffice is OfficeModel) {
      setState(() {
        _currentOffice = updatedOffice;
        // Clear cached widgets to force rebuild with new data
        _cachedMapWidget = null;
      });
    }
  }

  // Show delete confirmation dialog
  Future<void> _showDeleteConfirmation() async {
    final loc = AppLocalizations.of(context);
    final confirmed = await showDeleteConfirmationDialog(
      context,
      title: loc.translate('deleteOffice'),
      message: loc.translate('deleteOfficeConfirmationMessage'),
      itemIcon: FieldIcons.office,
      itemLabel: _currentOffice.officeName.isNotEmpty
          ? _currentOffice.officeName
          : loc.translate('office'),
    );

    if (confirmed == true && _currentOffice.id != null) {
      await _deleteOffice();
    }
  }

  // Delete the office and navigate back
  Future<void> _deleteOffice() async {
    final loc = AppLocalizations.of(context);

    try {
      await _officeService.deleteOffice(_currentOffice.id!);

      if (mounted) {
        _showToast(loc.translate('officeDeletedSuccessfully'),
            const Color(0xFF4CAF50));
        // Navigate back to the previous screen
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        _showToast(
            loc.translate('failedToDeleteOffice'), const Color(0xFFC81E1E));
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
