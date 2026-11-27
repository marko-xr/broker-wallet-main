import 'package:broker_wallet/src/views/Screens/ViewDetails/widgets/media_gallery_widget.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/widgets/media_loading_placeholder.dart';
import 'package:broker_wallet/src/views/Widgets/plan_attachment_details_card.dart';
import 'package:broker_wallet/src/config/supabase_config.dart';
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_models.dart';
import 'package:broker_wallet/src/services/plan_attachment/r2_plan_attachment_service.dart';
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_transport.dart';
import 'package:broker_wallet/src/viewmodels/plan_attachment_details_loader.dart';
import 'package:broker_wallet/src/services/fast_media_upload_service.dart';
import 'package:broker_wallet/src/services/offer_media_upload_queue.dart'
    show OfferMediaUploadCompleted;
import 'package:broker_wallet/src/views/Screens/ViewDetails/private_media_gallery_loader.dart';
import 'dart:async';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/utils/svg_icon.dart';
import 'package:broker_wallet/src/common/utils/map_coordinates.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/services/ScreenServices/owner_service.dart';
import 'package:broker_wallet/src/services/optimistic_favorites_service.dart';
import 'package:broker_wallet/src/views/Widgets/favorite_button.dart';
import 'package:broker_wallet/src/services/phone_input_service.dart';
import 'package:broker_wallet/src/services/details_contact_actions.dart';
import 'package:broker_wallet/src/services/share/share_models.dart';
import 'package:broker_wallet/src/services/share/share_sources.dart';
import 'package:broker_wallet/src/views/Widgets/share_options_dialog.dart';
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

import 'widgets/details_page.dart';
import 'widgets/details_media_placeholder.dart';
import 'widgets/details_section.dart';
import 'widgets/offer_details_style.dart';
import 'package:broker_wallet/src/views/Widgets/delete_confirmation_dialog.dart';
import 'package:broker_wallet/src/views/Widgets/field_icons.dart';

class OwnersDetailsView extends StatefulWidget {
  final OwnerModel owner;

  /// Optional local test dependencies; production keeps its existing services.
  final OwnerService? ownerService;
  final PlanAttachmentTransport? planTransport;
  final RelatedItemsService? relatedItemsService;

  const OwnersDetailsView({
    super.key,
    required this.owner,
    this.ownerService,
    this.planTransport,
    this.relatedItemsService,
  });

  @override
  State<OwnersDetailsView> createState() => _OwnersDetailsViewState();
}

class _OwnersDetailsViewState extends State<OwnersDetailsView>
    with TickerProviderStateMixin {
  late AnimationController _mainAnimationController;
  late AnimationController _fabAnimationController;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _fabAnimation;

  GoogleMapController? _mapController;
  PageController? _mediaPageController;
  final ScrollController _scrollController = ScrollController();

  // Services
  late final OwnerService _ownerService = widget.ownerService ?? OwnerService();
  late OptimisticFavoritesService _optimisticFavoritesService;
  late final RelatedItemsService _relatedItemsService =
      widget.relatedItemsService ?? RelatedItemsService();
  String? _relatedPhone;
  Stream<List<OfferModel>>? _relatedOffers;
  Stream<List<RequestModel>>? _relatedRequests;

  // Upload completion listener
  StreamSubscription<UploadCompletedEvent>? _uploadCompletionSubscription;

  // Owner private media (Supabase mode): the record's media, and the upload
  // queue's items for it and each one the server has accepted.
  PrivateMediaGalleryLoader? _mediaLoader;
  Listenable? _ownerMediaUploads;
  StreamSubscription<OfferMediaUploadCompleted>? _ownerMediaCompletions;

  // The Owner's land / plot plan (Supabase mode): its own optional attachment,
  // read separately from the gallery and shown in its own card.
  PlanAttachmentDetailsLoader? _planLoader;

  // Track current owner data (may be updated after edit)
  late OwnerModel _currentOwner;

  // Performance optimization: Cache expensive widgets
  Widget? _cachedMediaGallery;
  Widget? _cachedMapWidget;

  @override
  void initState() {
    super.initState();
    _currentOwner = widget.owner;
    _optimisticFavoritesService =
        Provider.of<OptimisticFavoritesService>(context, listen: false);
    _setupAnimations();
    _createMediaLoader();
    _initializeMediaController();
    _setupUploadCompletionListener();
    _setupOwnerMediaUploadListener();
    unawaited(_mediaLoader?.load());
    _createPlanLoader();
    unawaited(_planLoader?.load());
  }

  void _createPlanLoader() {
    final id = _currentOwner.id?.trim();
    if (!_usesPrivateMedia || id == null || id.isEmpty) return;
    _planLoader = PlanAttachmentDetailsLoader(
      parent: PlanParent.owner,
      parentId: id,
      transport: widget.planTransport ?? R2PlanAttachmentService(),
      onChanged: _handlePlanChanged,
    );
  }

  void _handlePlanChanged() {
    if (mounted) setState(() {});
  }

  /// The plan card, or nothing while the Owner has no plan (or it is not read
  /// yet): the screen never waits for it.
  Widget _buildPlanCard() {
    final loader = _planLoader;
    final plan = loader?.plan;
    if (loader == null || plan == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: PlanAttachmentDetailsCard(
        key: ValueKey('owner-plan-${plan.mediaObjectId}'),
        parent: PlanParent.owner,
        parentId: loader.parentId,
        plan: plan,
      ),
    );
  }

  /// Private R2 media, addressed by identity (Supabase mode). The legacy
  /// Firebase backend keeps showing the Owner's stored media URLs.
  bool get _usesPrivateMedia => SupabaseConfig.useSupabaseAuth;

  void _createMediaLoader() {
    final id = _currentOwner.id?.trim();
    if (!_usesPrivateMedia || id == null || id.isEmpty) return;
    _mediaLoader = PrivateMediaGalleryLoader(
      recordId: id,
      store: _ownerService,
      onChanged: _handleMediaChanged,
      // M2-3b (tracker §7AZ): the saved list's media identity, then a
      // read-only lookup of held bytes; the service applies every rule.
      recordOwnerId: _currentOwner.userId,
      listedMediaObjectIds: _currentOwner.listedMediaObjectIds,
      readListedMedia: _ownerService.listedMedia,
      discoverHeldMedia: _ownerService.discoverHeldMedia,
    );
  }

  void _setupOwnerMediaUploadListener() {
    if (_mediaLoader == null) return;
    try {
      final uploads = _ownerService.uploadChanges;
      uploads.addListener(_handleMediaChanged);
      _ownerMediaUploads = uploads;
      _ownerMediaCompletions = _ownerService.uploadCompletions.listen((event) {
        if (!mounted || event.offerId != _currentOwner.id) return;
        // The item is on the server now: show it from there.
        unawaited(_mediaLoader?.load());
      }, onError: (Object _) {});
      unawaited(_ownerService.loadUploads());
    } catch (_) {
      // Without the queue there is nothing pending to show.
    }
  }

  void _handleMediaChanged() {
    if (!mounted) return;
    setState(() {
      // Media can become drawable after this screen was first built, so the
      // pager is created on demand.
      _initializeMediaController();
      _cachedMediaGallery = null;
    });
  }

  /// Whether the header shows media (or its loading problem) rather than the
  /// plain gradient. An Owner with no media keeps the compact header.
  bool get _hasMediaHeader {
    final loader = _mediaLoader;
    if (loader != null) return loader.hasRenderableMedia || loader.loadFailed;
    return _currentOwner.mediaUrls.isNotEmpty;
  }

  /// Whether the header is showing the explained, retryable error state
  /// (icon + message + retry button), which needs the taller frame the
  /// gallery and placeholder states don't — the same distinction Offer
  /// Details makes with `hasRecoverableFailure`.
  bool get _hasRecoverableMediaFailure {
    final loader = _mediaLoader;
    return loader != null && loader.loadFailed && !loader.hasRenderableMedia;
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

  void _initializeMediaController() {
    if (_mediaPageController != null) return;
    final loader = _mediaLoader;
    final hasMedia = loader != null
        ? loader.hasRenderableMedia
        : _currentOwner.mediaUrls.isNotEmpty;
    if (hasMedia) {
      _mediaPageController = PageController();
    }
  }

  void _setupUploadCompletionListener() {
    _uploadCompletionSubscription = FastMediaUploadService.onUploadCompleted
        .where((event) =>
            event.collection == 'owners' &&
            event.documentId == _currentOwner.id)
        .listen((event) async {
      await _refreshOwnerData();
    });
  }

  Future<void> _refreshOwnerData() async {
    if (_currentOwner.id == null) return;

    try {
      final updatedOwner = await _ownerService.getOwner(_currentOwner.id!);
      if (updatedOwner != null && mounted) {
        setState(() {
          _currentOwner = updatedOwner;
          // Clear cached widgets to force rebuild with new media URLs
          _cachedMediaGallery = null;
          _cachedMapWidget = null;
        });
      }
    } catch (e) {}
  }

  @override
  void dispose() {
    _mediaLoader?.dispose();
    _planLoader?.dispose();
    _ownerMediaUploads?.removeListener(_handleMediaChanged);
    _ownerMediaCompletions?.cancel();
    _uploadCompletionSubscription?.cancel();
    _mainAnimationController.dispose();
    _fabAnimationController.dispose();
    _mediaPageController?.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final phone = _currentOwner.phoneNumber;
    final canContact = DetailsContactActions.normalizePhone(phone,
            countryCode: _currentOwner.countryCode) !=
        null;
    return DetailsPage(
      title: loc.translate('propertyOwner'),
      favorite: Consumer<OptimisticFavoritesService>(builder: _buildFavorite),
      onShare: _shareOwner,
      onEdit: _editOwner,
      onDelete: _showDeleteConfirmation,
      deleteLabel: loc.translate('deleteOwner'),
      onWhatsApp: !canContact ? null : () => _openWhatsApp(phone),
      onCall: !canContact ? null : () => _makePhoneCall(phone),
      scrollController: _scrollController,
      fade: _fadeAnimation,
      slide: _slideAnimation,
      contactFade: _fabAnimation,
      content: _buildCompactContent,
      media: _buildPropertyMedia,
    );
  }

  Widget _buildFavorite(BuildContext context,
      OptimisticFavoritesService favorites, Widget? child) {
    final id = _currentOwner.id;
    if (id == null) {
      return const Icon(Icons.favorite_border, size: 18);
    }
    return OptimizedFavoriteButton(
      size: 18,
      padding: const EdgeInsets.all((kMinInteractiveDimension - 18) / 2),
      isFavorite: favorites.isOwnerFavorite(id),
      isLoading: favorites.isOwnerLoading(id),
      onToggle: _toggleFavorite,
    );
  }

  Widget _buildPropertyMedia(BuildContext context) {
    final text = MediaQuery.textScalerOf(context);
    final isRecoverable = _hasRecoverableMediaFailure;
    final minHeight = isRecoverable ? 240.0 : 160.0;
    final referenceSize = isRecoverable ? 80.0 : 48.0;
    return ClipRRect(
      borderRadius:
          BorderRadius.circular(18 * OfferDetailsStyle.scale(context)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: minHeight +
              (text.scale(referenceSize) - referenceSize)
                  .clamp(0, double.infinity),
        ),
        child: AspectRatio(
          aspectRatio: 2.1,
          child: _hasMediaHeader
              ? _buildMediaHeader(context)
              : const DetailsMediaPlaceholder(asset: SvgIcon.ownersSvg),
        ),
      ),
    );
  }

  Widget _buildMediaHeader(BuildContext context) {
    final loader = _mediaLoader;
    if (loader == null) return _buildCachedMediaGallery();
    if (loader.hasRenderableMedia) return _buildPrivateMediaGallery(loader);
    return _buildMediaErrorHeader(context);
  }

  /// The Owner's private media: photos, videos (with their still frames,
  /// private playback and seeking) and this device's queued items with
  /// their upload state — the Offer Details gallery, for an Owner.
  Widget _buildPrivateMediaGallery(PrivateMediaGalleryLoader loader) {
    _cachedMediaGallery ??= OptimizedMediaGalleryWidget(
      mediaRefs: loader.displayItems,
      imagePlaceholder: const MediaLoadingPlaceholder(),
      pageController: _mediaPageController,
      showControls: true,
      autoPlay: false,
      fallbackSvgPath: 'assets/icons/profile-person.svg',
      onRetry: () => unawaited(loader.retry()),
      onRetryUpload: (mediaObjectId) =>
          unawaited(_ownerService.retryUpload(mediaObjectId)),
      onRemoveUpload: (mediaObjectId) =>
          unawaited(_ownerService.cancelUpload(mediaObjectId)),
      refreshSignedUrl: loader.refreshSignedUrl,
      onShareMedia: (key) => _shareOwner(initialMediaKey: key),
    );
    return _cachedMediaGallery!;
  }

  /// The Owner's media could not be loaded (nothing established about
  /// access): the same explained, retryable state as Offer Details.
  Widget _buildMediaErrorHeader(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final loc = AppLocalizations.of(context);
    return Container(
      color: colors.errorContainer,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.broken_image_outlined,
              size: 42,
              color: colors.onErrorContainer,
            ),
            const SizedBox(height: 8),
            Text(
              loc.translate('failedToLoadImage'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onErrorContainer,
                  ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => unawaited(_mediaLoader?.retry()),
              child: Text(loc.translate('retry')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCachedMediaGallery() {
    _cachedMediaGallery ??= OptimizedMediaGalleryWidget(
      mediaUrls: _currentOwner.mediaUrls,
      pageController: _mediaPageController,
      showControls: true,
      autoPlay: false,
      fallbackSvgPath: 'assets/icons/profile-person.svg',
      onShareMedia: (key) => _shareOwner(initialMediaKey: key),
    );
    return _cachedMediaGallery!;
  }

  Widget _buildCompactContent(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final name = _currentOwner.name.trim();
    final secondary = _currentOwner.propertyLocation.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DetailsSummary(
          title: name.isEmpty ? loc.translate('nameNotSpecified') : name,
          titleLabel: loc.translate('name'),
          titleMissing: name.isEmpty,
          icon: FieldIcons.location,
          subtitle: secondary.isEmpty ? null : secondary,
          subtitleLabel: loc.translate('propertyLocation'),
        ),
        const SizedBox(height: DetailsSection.spacing),
        DetailsFields(
          title: loc.translate('basicInformation'),
          rows: [
            DetailsField(
              icon: FieldIcons.specificType,
              label: loc.translate('propertyType'),
              isMissing: _currentOwner.typeOfProperties.trim().isEmpty,
              value: _currentOwner.typeOfProperties.trim().isNotEmpty
                  ? _currentOwner.typeOfProperties
                  : loc.translate('notSpecified'),
            ),
            if (secondary.isEmpty)
              DetailsField(
                icon: FieldIcons.location,
                label: loc.translate('propertyLocation'),
                value: loc.translate('propertyLocationNotSpecified'),
                isMissing: true,
              ),
            DetailsField(
              icon: FieldIcons.phone,
              label: loc.translate('phoneNumber'),
              isMissing: _currentOwner.phoneNumber.trim().isEmpty,
              value: _currentOwner.phoneNumber.trim().isNotEmpty
                  ? PhoneInputService.formatForDisplay(
                      _currentOwner.phoneNumber)
                  : loc.translate('phoneNotAdded'),
              onCopy: _currentOwner.phoneNumber.trim().isNotEmpty
                  ? _copyPhone
                  : null,
            ),
            ...DetailsDates.fields(context,
                createdAt: _currentOwner.createdAt,
                updatedAt: _currentOwner.updatedAt),
          ],
        ),
        if (_currentOwner.notes.isNotEmpty) ...[
          const SizedBox(height: DetailsSection.spacing),
          DetailsNotes(notes: _currentOwner.notes),
        ],
        _buildPlanCard(),
        const SizedBox(height: DetailsSection.spacing),
        _buildCompactLocationCard(context),
        _buildRelatedItemsCarousel(context),
      ],
    );
  }

  Widget _buildRelatedItemsCarousel(BuildContext context) {
    final phone = _currentOwner.phoneNumber;
    // Keep the same subscriptions through animation, resize and locale rebuilds.
    // An edited phone gets its own streams; the services still own refreshes.
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
        _currentOwner.pickUpLatitude, _currentOwner.pickUpLongitude);
    // Null, not a fallback string: when there's no address text, DetailsMap's
    // own "map not available" message already says so — showing a second,
    // separately-worded "no address" line next to it would just repeat it.
    final address = _currentOwner.pickUpAddress.trim().isNotEmpty
        ? _currentOwner.pickUpAddress
        : (_currentOwner.pickUpLocation.trim().isNotEmpty
            ? _currentOwner.pickUpLocation
            : null);
    return DetailsMap(
      title:
          loc.translate(hasMap ? 'propertyLocationOnMap' : 'propertyLocation'),
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
          child: GoogleMap(
            initialCameraPosition: CameraPosition(
              target: LatLng(
                _currentOwner.pickUpLatitude!,
                _currentOwner.pickUpLongitude!,
              ),
              zoom: 15,
            ),
            markers: {
              Marker(
                markerId: const MarkerId('pickup_location'),
                position: LatLng(
                  _currentOwner.pickUpLatitude!,
                  _currentOwner.pickUpLongitude!,
                ),
                infoWindow: InfoWindow(
                  title: _currentOwner.pickUpLocation,
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
            gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
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
        countryCode: _currentOwner.countryCode);
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
        countryCode: _currentOwner.countryCode);
    if (!mounted || result == ContactLaunchResult.opened) return;
    _showToast(
        loc.translate(result == ContactLaunchResult.invalidPhone
            ? 'phoneNumberNotAvailable'
            : 'unableToMakePhoneCall'),
        errorColor);
  }

  Future<void> _toggleFavorite() async {
    if (_currentOwner.id == null) return;

    final loc = AppLocalizations.of(context);
    // Capture theme colors before async operation
    final primaryColor = Theme.of(context).colorScheme.primary;
    final onSurfaceColor = Theme.of(context).colorScheme.onSurface;
    final errorColor = Theme.of(context).colorScheme.error;

    try {
      final newFavoriteStatus = await _optimisticFavoritesService
          .toggleOwnerFavorite(_currentOwner.id!);

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

  void _shareOwner({String? initialMediaKey}) {
    // The Owner's private photos and videos, as the gallery above holds them
    // (the legacy Firebase backend keeps plain stored links). They are attached
    // as files, fetched through the Owner's authorized media path.
    final loader = _mediaLoader;
    final refs = loader != null
        ? loader.displayItems
        : <OfferMediaRef>[
            for (final url in _currentOwner.mediaUrls)
              OfferMediaRef(
                mediaObjectId: '',
                cacheKey: null,
                signedUrl: url,
                isVideo: MediaItem.getMediaTypeFromUrl(url) == MediaType.video,
              ),
          ];
    ShareOptionsDialog.show(
      context,
      source: OwnerShareSource(
        _currentOwner,
        media: ShareMediaItem.fromRefs(refs),
      ),
      refreshLink: loader?.refreshSignedUrl,
      initialMediaKey: initialMediaKey,
    );
  }

  void _copyPhone() {
    final loc = AppLocalizations.of(context);

    if (_currentOwner.phoneNumber.isEmpty) {
      _showToast(loc.translate('noPhoneNumberToCopy'),
          Theme.of(context).colorScheme.error);
      return;
    }
    final dial = PhoneInputService.formatForDial(_currentOwner.phoneNumber);
    Clipboard.setData(ClipboardData(text: dial));
    _showToast(loc.translate('phoneNumberCopiedToClipboard'),
        Theme.of(context).colorScheme.primary);
  }

  void _openInMaps() async {
    final lat = _currentOwner.pickUpLatitude;
    final lng = _currentOwner.pickUpLongitude;

    // Only open if valid
    if (MapCoordinates.isValid(lat, lng)) {
      final uri = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=$lat,$lng');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        return;
      }
    }

    // Otherwise show the same clear message used in the placeholder
    if (!mounted) return;
    final loc = AppLocalizations.of(context);
    _showToast(loc.translate('mapLocationNotAvailable'),
        Theme.of(context).colorScheme.error);
  }

  void _editOwner() async {
    // Navigate to edit owner screen with data pre-filled
    final updatedOwner = await context.push(
      '/add-owners?mode=edit&id=${_currentOwner.id}',
      extra: _currentOwner, // Pass the current owner data
    );

    // If an updated owner was returned, update our state
    if (updatedOwner != null && updatedOwner is OwnerModel) {
      setState(() {
        _currentOwner = updatedOwner;
        // Clear cached widgets to force rebuild with new data
        _cachedMediaGallery = null;
        _cachedMapWidget = null;
      });
    }
    // Media may have been removed or added in the edit: read it again.
    if (mounted) unawaited(_mediaLoader?.load());
    // So may the land / plot plan.
    if (mounted) unawaited(_planLoader?.load());
  }

  // Show delete confirmation dialog
  Future<void> _showDeleteConfirmation() async {
    final loc = AppLocalizations.of(context);
    final confirmed = await showDeleteConfirmationDialog(
      context,
      title: loc.translate('deleteOwner'),
      message: loc.translate('deleteOwnerConfirmationMessage'),
      itemIcon: FieldIcons.name,
      itemLabel: _currentOwner.name.isNotEmpty
          ? _currentOwner.name
          : loc.translate('propertyOwner'),
    );

    if (confirmed == true && _currentOwner.id != null) {
      await _deleteOwner();
    }
  }

  // Delete the owner and navigate back
  Future<void> _deleteOwner() async {
    final loc = AppLocalizations.of(context);

    try {
      await _ownerService.deleteOwner(_currentOwner.id!);

      if (mounted) {
        _showToast(
            loc.translate('ownerDeletedSuccessfully'), const Color(0xFF4CAF50));
        // Navigate back to the previous screen
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        _showToast(
            loc.translate('failedToDeleteOwner'), const Color(0xFFC81E1E));
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
