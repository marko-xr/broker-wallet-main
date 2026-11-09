import 'dart:async';
import 'dart:io';
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'dart:ui' as ui;
import 'package:broker_wallet/src/Views/Screens/ViewDetails/offer_details_load_coordinator.dart';
import 'package:broker_wallet/src/Views/Screens/ViewDetails/widgets/media_gallery_widget.dart';
import 'package:broker_wallet/src/Views/Screens/ViewDetails/widgets/media_loading_placeholder.dart';
import 'package:broker_wallet/src/Views/Widgets/plan_attachment_details_card.dart';
import 'package:broker_wallet/src/config/supabase_config.dart';
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_models.dart';
import 'package:broker_wallet/src/services/plan_attachment/r2_plan_attachment_service.dart';
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_transport.dart';
import 'package:broker_wallet/src/viewmodels/plan_attachment_details_loader.dart';
import 'package:broker_wallet/src/services/fast_media_upload_service.dart';
import 'package:broker_wallet/src/services/share/share_sources.dart';
import 'package:broker_wallet/src/views/Widgets/share_options_dialog.dart';
import 'package:broker_wallet/src/services/share/share_models.dart';
import 'package:broker_wallet/src/Views/Widgets/property_status_indicator.dart';
import 'package:broker_wallet/src/services/optimistic_favorites_service.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/property_status.dart';
import 'package:broker_wallet/src/services/ScreenServices/offer_service.dart';
import 'package:broker_wallet/src/services/offer_media_upload_queue.dart'
    show OfferMediaUploadCompleted;
import 'package:broker_wallet/src/views/Screens/ViewDetails/widgets/offer_details_style.dart';
import 'package:broker_wallet/src/views/Widgets/offer_video_poster.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:broker_wallet/src/services/phone_input_service.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

class OffersDetailsView extends StatefulWidget {
  final OfferModel offer;

  /// True when [offer]'s core fields came from the authoritative ID loader.
  /// Private media still resolves independently after the screen is usable.
  final bool initialOfferIsResolved;
  final OfferMetadataLoader? loadMetadata;
  final OfferMediaResolver? resolveMedia;

  /// Media this device already holds for an Offer id, read synchronously.
  final CachedOfferMediaReader? readCachedMedia;

  /// This device's queued uploads for an Offer id, read synchronously.
  final PendingOfferMediaReader? readPendingMedia;
  final OfferService? offerService;
  final PlanAttachmentTransport? planTransport;

  const OffersDetailsView({
    super.key,
    required this.offer,
    this.initialOfferIsResolved = false,
    this.loadMetadata,
    this.resolveMedia,
    this.readCachedMedia,
    this.readPendingMedia,
    this.offerService,
    this.planTransport,
  });

  @override
  State<OffersDetailsView> createState() => _OffersDetailsViewState();
}

class _OffersDetailsViewState extends State<OffersDetailsView>
    with TickerProviderStateMixin {
  late AnimationController _mainAnimationController;
  late AnimationController _fabAnimationController;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _fabAnimation;

  GoogleMapController? _mapController;
  late final Future<BitmapDescriptor> _mapMarker = BitmapDescriptor.asset(
    const ImageConfiguration(size: Size(28, 28)),
    'assets/icons/markers/offer-marker.png',
    width: 28,
    height: 28,
  );
  PageController? _mediaPageController;
  int _currentMediaIndex = 0;
  final ScrollController _scrollController = ScrollController();

  // Services
  late final OfferService _offerService = widget.offerService ?? OfferService();

  // Upload completion listener
  StreamSubscription<UploadCompletedEvent>? _uploadCompletionSubscription;

  // Offer media upload queue (Supabase): its items' state, and each one the
  // server has accepted.
  Listenable? _offerMediaUploads;
  StreamSubscription<OfferMediaUploadCompleted>? _offerMediaCompletions;

  // Favorite state - now managed by OptimisticFavoritesService
  late OptimisticFavoritesService _optimisticFavoritesService;

  // Track current offer data (may be updated after edit)
  late OfferModel _currentOffer;
  late OfferDetailsLoadCoordinator _loadCoordinator;

  // The Offer's land / plot plan (Supabase mode): its own optional attachment,
  // read separately from the gallery and shown in its own card.
  PlanAttachmentDetailsLoader? _planLoader;

  // Performance optimization: Cache expensive widgets
  Widget? _cachedMediaGallery;
  Widget? _cachedMapWidget;

  @override
  void initState() {
    super.initState();
    _currentOffer = widget.offer; // Initialize with the passed offer
    _optimisticFavoritesService =
        Provider.of<OptimisticFavoritesService>(context, listen: false);
    _setupAnimations();
    _createLoadCoordinator();
    _initializeMediaController();
    _loadFavoriteStatus();
    _setupUploadCompletionListener();
    _setupOfferMediaUploadListener();
    unawaited(_loadCoordinator.load());
    _createPlanLoader();
    unawaited(_planLoader?.load());
  }

  void _createPlanLoader() {
    final id = _currentOffer.id?.trim();
    if (!SupabaseConfig.useSupabaseAuth || id == null || id.isEmpty) return;
    _planLoader = PlanAttachmentDetailsLoader(
      parent: PlanParent.offer,
      parentId: id,
      transport: widget.planTransport ?? R2PlanAttachmentService(),
      onChanged: _handlePlanChanged,
    );
  }

  void _handlePlanChanged() {
    if (mounted) setState(() {});
  }

  /// The plan card, or nothing while the Offer has no plan (or it is not read
  /// yet): the screen never waits for it.
  Widget _buildPlanCard() {
    final loader = _planLoader;
    final plan = loader?.plan;
    if (loader == null || plan == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: PlanAttachmentDetailsCard(
        key: ValueKey('offer-plan-${plan.mediaObjectId}'),
        parent: PlanParent.offer,
        parentId: loader.parentId,
        plan: plan,
      ),
    );
  }

  /// [resolvedOffer] is an Offer just read authoritatively (after Edit).
  void _createLoadCoordinator({OfferModel? resolvedOffer}) {
    _loadCoordinator = OfferDetailsLoadCoordinator(
      initialOffer: resolvedOffer ?? _currentOffer,
      initialMetadataResolved:
          resolvedOffer != null || widget.initialOfferIsResolved,
      loadMetadata: widget.loadMetadata ?? _offerService.getOfferMetadata,
      resolveMedia: widget.resolveMedia ?? _offerService.resolveOfferMedia,
      readCachedMedia: widget.readCachedMedia ?? _offerService.cachedOfferMedia,
      readPendingMedia:
          widget.readPendingMedia ?? _offerService.pendingOfferMedia,
      onChanged: _handleLoadChanged,
    );
  }

  void _setupOfferMediaUploadListener() {
    try {
      final uploads = _offerService.offerMediaUploadChanges;
      uploads.addListener(_handleOfferMediaUploadsChanged);
      _offerMediaUploads = uploads;
      _offerMediaCompletions =
          _offerService.offerMediaUploadCompletions.listen((event) {
        if (!mounted || event.offerId != _currentOffer.id) return;
        // The item is on the server now: show it from there.
        unawaited(_loadCoordinator.load());
      }, onError: (Object _) {});
      unawaited(_offerService.loadOfferMediaUploads());
    } catch (_) {
      // Without the queue there is nothing pending to show.
    }
  }

  void _handleOfferMediaUploadsChanged() {
    if (!mounted) return;
    setState(() {
      _initializeMediaController();
      _cachedMediaGallery = null;
    });
  }

  void _retryOfferMediaUpload(String mediaObjectId) {
    unawaited(_offerService.retryOfferMediaUpload(mediaObjectId));
  }

  void _removeOfferMediaUpload(String mediaObjectId) {
    unawaited(_offerService.cancelOfferMediaUpload(mediaObjectId));
  }

  void _handleLoadChanged() {
    if (!mounted) return;
    setState(() {
      _currentOffer = _loadCoordinator.offer;
      // Media can become drawable after this screen was first built — either
      // from the authoritative resolution or, on a cold cache, as soon as the
      // first bytes land — so the pager is created on demand.
      _initializeMediaController();
      _cachedMediaGallery = null;
      _cachedMapWidget = null;
    });
  }

  @override
  void didUpdateWidget(covariant OffersDetailsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.offer.id != widget.offer.id) {
      _loadCoordinator.dispose();
      _currentOffer = widget.offer;
      _cachedMediaGallery = null;
      _cachedMapWidget = null;
      _currentMediaIndex = 0;
      _mediaPageController?.dispose();
      _mediaPageController = null;
      _createLoadCoordinator();
      _initializeMediaController();
      _loadFavoriteStatus();
      unawaited(_loadCoordinator.load());
      _planLoader?.dispose();
      _planLoader = null;
      _createPlanLoader();
      unawaited(_planLoader?.load());
    }
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
      curve: Curves.easeOut,
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
    if (_loadCoordinator.hasRenderableMedia) {
      _mediaPageController = PageController();
    }
  }

  void _loadFavoriteStatus() async {
    if (_currentOffer.id != null) {
      await _optimisticFavoritesService.initializeFavoriteStatus(
          _currentOffer.id!, 'offers');
    }
  }

  void _setupUploadCompletionListener() {
    _uploadCompletionSubscription = FastMediaUploadService.onUploadCompleted
        .where((event) =>
            event.collection == 'offers' &&
            event.documentId == _currentOffer.id)
        .listen((event) async {
      await _loadCoordinator.reload();
    });
  }

  void _retryOfferLoad() {
    unawaited(_loadCoordinator.retry());
  }

  @override
  void dispose() {
    _loadCoordinator.dispose();
    _planLoader?.dispose();
    _uploadCompletionSubscription?.cancel();
    _offerMediaUploads?.removeListener(_handleOfferMediaUploadsChanged);
    _offerMediaCompletions?.cancel();
    _mainAnimationController.dispose();
    _fabAnimationController.dispose();
    _mediaPageController?.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: OfferDetailsStyle.theme(Theme.of(context),
          scale: OfferDetailsStyle.scale(context)),
      child: Builder(builder: _buildScreen),
    );
  }

  Widget _buildScreen(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    if (_loadCoordinator.detailsUnavailable) {
      final loc = AppLocalizations.of(context);
      return Scaffold(
        backgroundColor: colors.surface,
        appBar: AppBar(backgroundColor: colors.surface),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: colors.error,
              ),
              const SizedBox(height: 16),
              Text(
                loc.translate('offerNotFound'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/home');
                  }
                },
                child: Text(loc.translate('goBack')),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: colors.surface,
      body: AnimatedBuilder(
        animation: _mainAnimationController,
        builder: (context, child) {
          return CustomScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            slivers: [
              _buildModernAppBar(context),
              SliverToBoxAdapter(child: _buildPropertyMedia(context)),
              SliverToBoxAdapter(
                child: Transform.translate(
                  offset: Offset(0, 40 * _slideAnimation.value),
                  child: Opacity(
                    opacity: _fadeAnimation.value,
                    child: _buildCompactContent(context),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: _buildContactBar(context),
    );
  }

  Widget _buildModernAppBar(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final loc = AppLocalizations.of(context);
    final scale = OfferDetailsStyle.scale(context);
    return SliverAppBar(
      pinned: true,
      toolbarHeight: 48 * scale,
      backgroundColor: colors.surface,
      surfaceTintColor: colors.surface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      leadingWidth: 52 * scale,
      title: Text(loc.translate('propertyDetails'),
          style: Theme.of(context).textTheme.titleLarge),
      leading: Padding(
        padding: EdgeInsetsDirectional.only(start: 18 * scale),
        child: _headerAction(context,
            tooltip: loc.translate('goBack'),
            icon: Directionality.of(context) == ui.TextDirection.rtl
                ? Icons.chevron_right
                : Icons.chevron_left,
            onPressed: () => context.pop()),
      ),
      actions: [
        Consumer<OptimisticFavoritesService>(
          builder: (context, favorites, child) {
            final selected = _currentOffer.id != null &&
                favorites.isOfferFavorite(_currentOffer.id!);
            return _headerAction(context,
                tooltip: loc.translate('favorites'),
                icon: selected ? Icons.favorite : Icons.favorite_border,
                color: selected ? colors.primary : colors.onSurface,
                onPressed: _currentOffer.id == null ||
                        favorites.isOfferLoading(_currentOffer.id!)
                    ? null
                    : _toggleFavorite);
          },
        ),
        SizedBox(width: 8 * scale),
        _headerAction(context,
            tooltip: loc.translate('share'),
            icon: Icons.share_outlined,
            onPressed: _showShareDialog),
        SizedBox(width: 18 * scale),
      ],
    );
  }

  Widget _headerAction(BuildContext context,
      {required String tooltip,
      required IconData icon,
      Color? color,
      required VoidCallback? onPressed}) {
    final colors = Theme.of(context).colorScheme;
    final scale = OfferDetailsStyle.scale(context);
    return Center(
        child: Container(
      width: 34 * scale,
      height: 34 * scale,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.surfaceContainerLowest,
        boxShadow: [
          BoxShadow(
              color: colors.shadow.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, size: 21 * scale, textDirection: ui.TextDirection.ltr),
        color: color ?? colors.onSurface,
        padding: EdgeInsets.zero,
        onPressed: onPressed,
      ),
    ));
  }

  Widget _buildPropertyMedia(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(12 * OfferDetailsStyle.scale(context), 8,
          12 * OfferDetailsStyle.scale(context), 0),
      child: Column(
        children: [
          ClipRRect(
            borderRadius:
                BorderRadius.circular(18 * OfferDetailsStyle.scale(context)),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  minHeight: _loadCoordinator.hasRecoverableFailure
                      ? 240 + MediaQuery.textScalerOf(context).scale(80) - 80
                      : 160 + MediaQuery.textScalerOf(context).scale(48) - 48),
              child: AspectRatio(
                aspectRatio: 2.1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildHeaderBackground(
                        context,
                        _currentOffer.offerType == 'rent',
                        colors,
                        Theme.of(context).textTheme),
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
          ),
          if (_loadCoordinator.displayItems.length > 1) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 56 * OfferDetailsStyle.scale(context),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _loadCoordinator.displayItems.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final item = _loadCoordinator.displayItems[index];
                  final local =
                      item.isVideo ? item.posterPath : item.localFilePath;
                  final fallback = Icon(
                      item.isVideo
                          ? Icons.play_circle_outline
                          : Icons.image_outlined,
                      color: colors.primary);
                  return Semantics(
                    label:
                        '${index + 1} / ${_loadCoordinator.displayItems.length}',
                    selected: index == _currentMediaIndex,
                    button: true,
                    child: InkWell(
                      key: ValueKey('offer-thumbnail-${item.mediaObjectId}'),
                      onTap: () => _mediaPageController?.animateToPage(index,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: (MediaQuery.sizeOf(context).width -
                                24 * OfferDetailsStyle.scale(context) -
                                32) /
                            5,
                        padding:
                            EdgeInsets.all(index == _currentMediaIndex ? 2 : 0),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: index == _currentMediaIndex
                                ? colors.primary
                                : colors.surface,
                            width: index == _currentMediaIndex ? 1.5 : 0,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(11),
                          child: item.isVideo
                              ? OfferVideoPoster(
                                  cacheKey: item.cacheKey,
                                  posterPath: item.posterPath,
                                  signedUrl:
                                      item.signedUrl ?? item.localFilePath,
                                  placeholder: Center(child: fallback),
                                  frameOverlay: Center(
                                      child: Icon(Icons.play_circle_outline,
                                          color: colors.onPrimary, size: 22)),
                                  cacheWidth: 240,
                                )
                              : local != null &&
                                      local.isNotEmpty &&
                                      File(local).existsSync()
                                  ? Image.file(File(local),
                                      fit: BoxFit.cover,
                                      cacheWidth: 240,
                                      errorBuilder: (_, __, ___) => fallback)
                                  : OfflineMediaService.instance
                                      .buildOfflineAwareImage(
                                          imageUrl: item.signedUrl ?? '',
                                          cacheKey: item.cacheKey,
                                          fit: BoxFit.cover,
                                          cacheWidth: 240,
                                          placeholder: fallback,
                                          errorWidget: fallback),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusBadge(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final loc = AppLocalizations.of(context);
    final available = _currentOffer.status == PropertyStatus.available;
    final label = available
        ? loc.translate(_currentOffer.offerType == 'rent'
            ? 'offerDetailsAvailableForRent'
            : 'offerDetailsAvailableForSale')
        : _getLocalizedStatusLabel();
    return Material(
      color: Color.alphaBlend(colors.primary.withValues(alpha: 0.12),
          colors.surfaceContainerLowest),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: _currentOffer.id == null ? null : _showStatusSelector,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(available ? Icons.circle : _statusIcon(_currentOffer.status),
                size: available ? 6 : 12, color: colors.primary),
            const SizedBox(width: 6),
            Flexible(
                child: Text(label,
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: colors.primary))),
          ]),
        ),
      ),
    );
  }

  Widget _buildHeaderBackground(
    BuildContext context,
    bool isRent,
    ColorScheme colors,
    TextTheme texts,
  ) {
    // Locally held bytes render here on the very first frame, before any
    // network call — the gallery is shown as soon as anything is drawable
    // rather than waiting for a freshly signed URL.
    if (_loadCoordinator.hasRenderableMedia) {
      return _buildCachedMediaGallery();
    }
    if (_loadCoordinator.isLoading) {
      return _buildMediaLoadingHeader(context);
    }
    // Proven gone for this account: a settled, explained state with no retry,
    // because retrying cannot change the answer.
    if (_loadCoordinator.mediaAccessRevoked) {
      return _buildMediaUnavailableHeader(context);
    }
    if (_loadCoordinator.hasRecoverableFailure) {
      return _buildMediaErrorHeader(context);
    }
    return _buildGradientHeader(context, isRent, colors, texts);
  }

  /// The media area while the Offer's photos are still being resolved.
  ///
  /// Identical to what the gallery draws for an image whose bytes have not
  /// arrived, so the moment the gallery takes over is invisible: the first
  /// open shows one continuous surface, not a spinner followed by a second,
  /// different spinner.
  Widget _buildMediaLoadingHeader(BuildContext context) =>
      const MediaLoadingPlaceholder();

  /// Media the server says this account no longer has.
  ///
  /// Deliberately neutral: no retry, and no provider text. The local copy has
  /// already been removed by the time this is drawn.
  Widget _buildMediaUnavailableHeader(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final loc = AppLocalizations.of(context);
    return Container(
      color: colors.surfaceContainerHighest,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_not_supported_outlined,
              size: 42,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              loc.translate('offerMediaUnavailable'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaErrorHeader(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final loc = AppLocalizations.of(context);
    final messageKey = _loadCoordinator.metadataLoadFailed
        ? 'errorLoadingData'
        : 'failedToLoadImage';
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
              loc.translate(messageKey),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onErrorContainer,
                  ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: _retryOfferLoad,
              child: Text(loc.translate('retry')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleFavorite() async {
    if (_currentOffer.id == null) return;

    // Capture theme colors before async operation
    final loc = AppLocalizations.of(context);
    final primaryColor = Theme.of(context).colorScheme.primary;
    final onSurfaceColor = Theme.of(context).colorScheme.onSurface;
    final errorColor = Theme.of(context).colorScheme.error;

    try {
      final newFavoriteStatus = await _optimisticFavoritesService
          .toggleOfferFavorite(_currentOffer.id!);

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

  Widget _buildCachedMediaGallery() {
    _cachedMediaGallery ??= OptimizedMediaGalleryWidget(
      mediaRefs: _loadCoordinator.displayItems,
      imagePlaceholder: const MediaLoadingPlaceholder(),
      pageController: _mediaPageController,
      onPageChanged: (index) {
        setState(() {
          _currentMediaIndex = index;
        });
      },
      showControls: false,
      compactPresentation: true,
      autoPlay: false,
      fallbackSvgPath: 'assets/icons/building-property.svg',
      onRetry: _retryOfferLoad,
      onRetryUpload: _retryOfferMediaUpload,
      onRemoveUpload: _removeOfferMediaUpload,
      refreshSignedUrl: (mediaObjectId) =>
          _loadCoordinator.refreshSignedUrl(mediaObjectId),
      onShareMedia: (key) => _showShareDialog(initialMediaKey: key),
    );
    return _cachedMediaGallery!;
  }

  Widget _buildGradientHeader(
      BuildContext context, bool isRent, ColorScheme colors, TextTheme texts) {
    return ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Center(
        child:
            Icon(Icons.home_outlined, size: 56, color: colors.onSurfaceVariant),
      ),
    );
  }

  Widget _buildCompactContent(BuildContext context) {
    final scale = OfferDetailsStyle.scale(context);
    return RepaintBoundary(
        child: Padding(
      padding: EdgeInsets.fromLTRB(13 * scale, 14 * scale, 13 * scale, 20),
      child: Column(children: [
        _buildHeroCard(context),
        SizedBox(height: 12 * scale),
        _buildPropertyStats(context),
        SizedBox(height: 9 * scale),
        _buildDetailsCard(context),
        if (_currentOffer.notes.isNotEmpty) ...[
          SizedBox(height: 8 * scale),
          _buildCompactNotesCard(context),
        ],
        _buildPlanCard(),
        SizedBox(height: 8 * scale),
        _buildCompactLocationCard(context),
      ]),
    ));
  }

  Widget _buildHeroCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;
    final loc = AppLocalizations.of(context);
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_getPropertyDisplayText(),
            style: texts.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 7),
        Row(children: [
          Icon(Icons.location_on, color: colors.primary, size: 14),
          const SizedBox(width: 6),
          Expanded(
              child: Text(
                  _getLocationText().isNotEmpty
                      ? _getLocationText()
                      : loc.translate('locationNotSpecified'),
                  style: texts.bodyMedium)),
        ]),
      ],
    );
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 328 ||
          MediaQuery.textScalerOf(context).scale(1) > 1.3) {
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              const SizedBox(height: 12),
              _buildPriceDisplay(context),
            ]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(child: title),
        const SizedBox(width: 10),
        Expanded(child: _buildPriceDisplay(context)),
      ]);
    });
  }

  Widget _buildWhatsAppButton(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return FilledButton.icon(
      onPressed: _currentOffer.phoneNumber.isEmpty
          ? null
          : () => _openWhatsApp(
              _currentOffer.phoneNumber, loc.translate('propertyManager')),
      icon: FaIcon(FontAwesomeIcons.whatsapp,
          size: 21 * OfferDetailsStyle.scale(context)),
      label: Text(loc.translate('whatsapp')),
      style: FilledButton.styleFrom(
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        textStyle: Theme.of(context).textTheme.labelLarge,
        minimumSize: Size(0, 36 * OfferDetailsStyle.scale(context)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
    );
  }

  Widget _buildCallButton(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return OutlinedButton.icon(
      onPressed: _currentOffer.phoneNumber.isEmpty
          ? null
          : () => _makePhoneCall(_currentOffer.phoneNumber),
      icon: const Icon(Icons.phone_rounded, size: 18),
      label: Text(AppLocalizations.of(context).translate('call')),
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.primary,
        textStyle: Theme.of(context).textTheme.labelLarge,
        minimumSize: Size(0, 36 * OfferDetailsStyle.scale(context)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        side: BorderSide(
            color: colors.primary.withValues(alpha: 0.7), width: 0.8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
    );
  }

  // WhatsApp functionality
  Future<void> _openWhatsApp(String phoneNumber, String managerName) async {
    final loc = AppLocalizations.of(context);
    try {
      // Use project's phone helper to produce a dial-friendly string
      final formattedNumber = PhoneInputService.formatForDial(phoneNumber);

      String template = loc.translate('whatsAppBusinessMessage');
      if (template.startsWith('** ')) {
        template =
            'Hello {managerName}, I would like to discuss business opportunities with your office.';
      }
      final messageText = template.replaceAll('{managerName}', managerName);
      final message = Uri.encodeComponent(messageText);

      // Try direct app URL first
      final directAppUri = Uri.parse(
          'https://api.whatsapp.com/send?phone=$formattedNumber&text=%22$message%22');

      if (await canLaunchUrl(directAppUri)) {
        await launchUrl(
          directAppUri,
          mode: LaunchMode.externalApplication,
        );
        return;
      }

      // Fallback to native URI
      final nativeUri =
          Uri.parse('https://wa.me/$formattedNumber?text=$message');
      if (await canLaunchUrl(nativeUri)) {
        await launchUrl(
          nativeUri,
          mode: LaunchMode.externalApplication,
        );
        return;
      }

      // Last fallback to web WhatsApp
      final webUri = Uri.parse(
          'https://web.whatsapp.com/send?phone=$formattedNumber&text=$message');
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('WhatsApp error: $e');
      if (context.mounted) {
        _showToast(
          loc.translate('couldNotOpenWhatsApp'),
          Theme.of(context).colorScheme.error,
        );
      }
    }
  }

  Widget _buildPriceDisplay(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;
    final loc = AppLocalizations.of(context);
    String amount(String raw) {
      final number = num.tryParse(raw.replaceAll(',', '').trim());
      return number == null
          ? raw.trim()
          : NumberFormat('#,##0.##', 'en').format(number);
    }

    final min = amount(_currentOffer.minPrice);
    final max = amount(_currentOffer.maxPrice);
    final currency = loc.translate('offerDetailsCurrency');
    final hasPrice = min.isNotEmpty || max.isNotEmpty;
    final price = min.isNotEmpty && max.isNotEmpty
        ? '$currency $min - $max'
        : min.isNotEmpty
            ? '${loc.translate('from')} $currency $min'
            : max.isNotEmpty
                ? '${loc.translate('upTo')} $currency $max'
                : loc.translate('priceNotSpecified');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
          decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20)),
          child: Text(
              loc.translate(
                  _currentOffer.offerType == 'rent' ? 'rent' : 'sale'),
              style: texts.labelSmall
                  ?.copyWith(color: colors.primary, height: 1.1)),
        ),
        const SizedBox(height: 3),
        if (hasPrice)
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(price,
                textDirection: ui.TextDirection.ltr,
                maxLines: 1,
                style: texts.titleLarge?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w800,
                    height: 1.1)),
          )
        else
          Text(price, style: texts.bodyMedium?.copyWith(color: colors.primary)),
      ]),
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

    // Treat comma as thousands separator by default.
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
        _buildStatItem(Icons.bed_outlined, _currentOffer.rooms.toString(),
            loc.translate('offerDetailsBedrooms'), colors, texts),
        _buildStatItem(
            Icons.bathtub_outlined,
            _currentOffer.bathrooms.toString(),
            loc.translate('bathrooms'),
            colors,
            texts),
      ],
      _buildStatItem(
          Icons.square_foot,
          _currentOffer.squareFootage.trim().isEmpty
              ? loc.translate('squareFootageNotSpecified')
              : '${_formatSquareFootage(_currentOffer.squareFootage)} ${loc.translate('squareFootageUnit')}',
          loc.translate('offerDetailsArea'),
          colors,
          texts),
    ];
    return Container(
      key: const ValueKey('offer-details-stats'),
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

  BoxDecoration _sectionDecoration(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return BoxDecoration(
      color: colors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
          color: colors.onSurface.withValues(alpha: 0.025), width: 0.7),
      boxShadow: [
        BoxShadow(
            color: colors.shadow.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 6))
      ],
    );
  }

  Widget _buildDetailsCard(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final rows = <Widget>[
      _buildDetailRow(
          context,
          Icons.sell_outlined,
          loc.translate('offerType'),
          loc.translate(
              _currentOffer.offerType == 'rent' ? 'rentOffer' : 'saleOffer')),
      _buildDetailRow(
          context,
          Icons.location_city_outlined,
          loc.translate('city'),
          _currentOffer.selectedCity.isNotEmpty
              ? _getLocalizedCityName(_currentOffer.selectedCity)
              : loc.translate('cityNotSpecified')),
      _buildDetailRow(
          context,
          Icons.place_outlined,
          loc.translate('areas'),
          _currentOffer.selectedAreas.isNotEmpty
              ? _getLocalizedAreasText(_currentOffer.selectedAreas)
              : loc.translate('areasNotSpecified')),
      _buildDetailRow(
          context,
          Icons.phone_outlined,
          loc.translate('phoneNumber'),
          _currentOffer.phoneNumber.isNotEmpty
              ? PhoneInputService.formatForDisplay(_currentOffer.phoneNumber)
              : loc.translate('phoneNotAdded'),
          onTap: _currentOffer.phoneNumber.isNotEmpty ? _copyPhone : null,
          isPhone: true),
      _buildDetailRow(
          context,
          Icons.map_outlined,
          loc.translate('location'),
          _currentOffer.location.isNotEmpty
              ? _currentOffer.location
              : loc.translate('specificLocationNotProvided')),
    ];
    return Container(
      key: const ValueKey('offer-details-card'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: _sectionDecoration(context),
      child: Column(children: [
        Row(children: [
          Icon(Icons.description_outlined, color: colors.primary, size: 18),
          const SizedBox(width: 7),
          Expanded(
              child: Text(loc.translate('propertyDetails'),
                  style: Theme.of(context).textTheme.titleMedium)),
          PopupMenuButton<String>(
            tooltip: loc.translate('offerDetailsActions'),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 120),
            child: SizedBox(
                width: 24,
                height: 24,
                child: Icon(Icons.more_horiz,
                    size: 16, color: colors.onSurfaceVariant)),
            onSelected: (value) {
              if (value == 'edit') _editOffer();
              if (value == 'delete') _showDeleteConfirmation();
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'edit', child: Text(loc.translate('edit'))),
              PopupMenuItem(
                  value: 'delete', child: Text(loc.translate('deleteOffer'))),
            ],
          ),
        ]),
        const SizedBox(height: 2),
        IntrinsicHeight(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final row in rows) Expanded(child: row)],
          ),
        ),
      ]),
    );
  }

  Widget _buildDetailRow(
      BuildContext context, IconData icon, String label, String value,
      {VoidCallback? onTap, bool isPhone = false}) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;
    return InkWell(
        key: ValueKey('offer-detail-row-$label'),
        onTap: onTap,
        child: Container(
          // A shared floor prevents short Arabic content from collapsing
          // the spacing. Longer values can still increase every row's height.
          constraints: BoxConstraints(
              minHeight: kMinInteractiveDimension *
                  MediaQuery.textScalerOf(context)
                      .scale(1)
                      .clamp(1.0, double.infinity)),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(
                      color: colors.onSurface.withValues(alpha: 0.07),
                      width: 0.5))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Icon(icon, size: 15, color: colors.onSurfaceVariant),
            const SizedBox(width: 7),
            Expanded(flex: 4, child: Text(label, style: texts.bodyMedium)),
            const SizedBox(width: 10),
            Expanded(
                flex: 6,
                child: Text(value,
                    textAlign:
                        Directionality.of(context) == ui.TextDirection.rtl
                            ? TextAlign.left
                            : TextAlign.right,
                    textDirection: isPhone ? ui.TextDirection.ltr : null,
                    style: texts.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600))),
            if (onTap != null) ...[
              const SizedBox(width: 5),
              Icon(Icons.copy_outlined, size: 13, color: colors.primary),
            ],
          ]),
        ));
  }

  Widget _buildCompactLocationCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;
    final loc = AppLocalizations.of(context);
    final hasMap = _hasValidLatLng(
        _currentOffer.pickUpLatitude, _currentOffer.pickUpLongitude);
    return Container(
      key: const ValueKey('offer-details-map'),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      decoration: _sectionDecoration(context),
      child: Column(children: [
        Row(children: [
          Icon(Icons.location_on_outlined, color: colors.primary, size: 19),
          const SizedBox(width: 7),
          Expanded(
              child: Text(loc.translate('offerDetailsMapTitle'),
                  style: texts.titleMedium)),
          Expanded(
              child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton.icon(
                      key: const ValueKey('offer-details-view-larger'),
                      onPressed: hasMap ? _openInMaps : null,
                      icon: const Icon(Icons.open_in_new, size: 13),
                      label: Text(loc.translate('offerDetailsViewLarger')),
                      style: TextButton.styleFrom(
                          textStyle: texts.labelSmall,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          minimumSize: const Size(0, 28),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap)))),
        ]),
        const SizedBox(height: 4),
        if (hasMap)
          _buildCachedMiniMap(context)
        else
          Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Icon(Icons.location_off_outlined,
                    size: 18, color: colors.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(loc.translate('mapLocationNotAvailable'),
                        style: texts.bodyMedium)),
              ])),
      ]),
    );
  }

  Widget _buildCachedMiniMap(BuildContext context) {
    _cachedMapWidget ??= GestureDetector(
      onTap: _openInMaps,
      child: SizedBox(
        height: 64 * OfferDetailsStyle.scale(context),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: FutureBuilder<BitmapDescriptor>(
            future: _mapMarker,
            builder: (context, marker) => GoogleMap(
              initialCameraPosition: CameraPosition(
                target: LatLng(
                  _currentOffer.pickUpLatitude!,
                  _currentOffer.pickUpLongitude!,
                ),
                zoom: 15,
              ),
              markers: {
                Marker(
                  markerId: const MarkerId('pickup_location'),
                  icon: marker.data ??
                      BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueGreen),
                  position: LatLng(
                    _currentOffer.pickUpLatitude!,
                    _currentOffer.pickUpLongitude!,
                  ),
                  infoWindow: InfoWindow(
                    title: _currentOffer.pickUpLocation,
                  ),
                  onTap: () => _openInMaps(),
                ),
              },
              onMapCreated: (GoogleMapController controller) {
                _mapController = controller;
              },
              onTap: (LatLng latLng) => _openInMaps(),
              myLocationButtonEnabled: false,
              compassEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              gestureRecognizers: const <Factory<
                  OneSequenceGestureRecognizer>>{},
            ),
          ),
        ),
      ),
    );

    return _cachedMapWidget!;
  }

  Widget _buildCompactNotesCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: _sectionDecoration(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.description_outlined, color: colors.primary, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(AppLocalizations.of(context).translate('notes'),
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold))),
        ]),
        const SizedBox(height: 6),
        Text(_currentOffer.notes,
            style:
                Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5)),
      ]),
    );
  }

  Widget _buildContactBar(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FadeTransition(
      opacity: _fabAnimation,
      child: Container(
        decoration: BoxDecoration(color: colors.surface, boxShadow: [
          BoxShadow(
              color: colors.shadow.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, -4)),
        ]),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16 * OfferDetailsStyle.scale(context),
                10, 16 * OfferDetailsStyle.scale(context), 8),
            child: Row(children: [
              Expanded(child: _buildWhatsAppButton(context)),
              const SizedBox(width: 8),
              Expanded(child: _buildCallButton(context)),
            ]),
          ),
        ),
      ),
    );
  }

  String _getLocalizedStatusLabel() {
    final loc = AppLocalizations.of(context);
    final statusKey = _currentOffer.status.name;
    final translated = loc.translate(statusKey);

    if (translated.startsWith('** ')) {
      return _currentOffer.status.displayName;
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

  // Helper methods

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

  String _getPropertyDisplayText() {
    if (_currentOffer.specificPropertyType.isEmpty) {
      return '';
    }

    String propertyText =
        _getLocalizedSpecificType(_currentOffer.specificPropertyType);
    if (_currentOffer.propertyType != null &&
        _currentOffer.propertyType!.isNotEmpty) {
      String localizedPropertyType =
          _getLocalizedPropertyType(_currentOffer.propertyType!);
      propertyText = '$propertyText $localizedPropertyType';
    }
    return propertyText;
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

  String _getLocationText() {
    final loc = AppLocalizations.of(context);
    List<String> locationParts = [];

    if (_currentOffer.selectedAreas.isNotEmpty) {
      // Use localized area name
      String firstArea = _currentOffer.selectedAreas.first;
      String areaKey = _areaLocalizationKey(firstArea);
      String localizedArea = loc.translate(areaKey);

      // If translation not found, use original
      if (localizedArea == '** $areaKey not found') {
        locationParts.add(firstArea);
      } else {
        locationParts.add(localizedArea);
      }
    }

    if (_currentOffer.selectedCity.isNotEmpty) {
      // Use localized city name
      String cityKey = _cityLocalizationKey(_currentOffer.selectedCity);
      String localizedCity = loc.translate(cityKey);

      // If translation not found, use original
      if (localizedCity == '** $cityKey not found') {
        locationParts.add(_currentOffer.selectedCity);
      } else {
        locationParts.add(localizedCity);
      }
    }

    return locationParts.join(', ');
  }

  bool _shouldShowRoomsAndBaths() {
    final allowedTypes = ['villa', 'apartment', 'studio'];
    return allowedTypes
        .contains(_currentOffer.specificPropertyType.toLowerCase());
  }

  // Action methods
  void _showShareDialog({String? initialMediaKey}) {
    // Built from the Offer as this screen holds it, so the text works offline
    // and shares this Offer's own phone number (the one shown above). Photos and
    // videos are attached as files, fetched through this Offer's authorized
    // media path; their links are never shared.
    ShareOptionsDialog.show(
      context,
      source: PropertyShareSource.offer(
        _currentOffer,
        media: ShareMediaItem.fromRefs(_loadCoordinator.displayItems),
      ),
      refreshLink: _loadCoordinator.refreshSignedUrl,
      initialMediaKey: initialMediaKey,
    );
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final loc = AppLocalizations.of(context);
    if (phoneNumber.isEmpty) {
      _showToast(loc.translate('phoneNumberNotAvailable'),
          Theme.of(context).colorScheme.error);
      return;
    }

    final dial = PhoneInputService.formatForDial(phoneNumber);
    final Uri phoneUri = Uri(scheme: 'tel', path: dial);
    try {
      await launchUrl(phoneUri, mode: LaunchMode.platformDefault);
    } on PlatformException catch (e) {
      debugPrint('Failed to open dialer: ${e.message}');
      _showToast(loc.translate('unableToMakePhoneCall'),
          Theme.of(context).colorScheme.error);
    }
  }

  Future<void> _copyPhone() async {
    final loc = AppLocalizations.of(context);
    if (_currentOffer.phoneNumber.isEmpty) {
      _showToast(loc.translate('noPhoneNumberToCopy'),
          Theme.of(context).colorScheme.error);
      return;
    }

    final dial = PhoneInputService.formatForDial(_currentOffer.phoneNumber);
    await Clipboard.setData(ClipboardData(
      text: dial,
    ));
    _showToast(loc.translate('phoneNumberCopied'),
        Theme.of(context).colorScheme.primary);
  }

  bool _hasValidLatLng(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    if (lat == 0.0 && lng == 0.0) return false; // avoid Null Island
    if (lat < -90 || lat > 90) return false;
    if (lng < -180 || lng > 180) return false;
    return true;
  }

  void _openInMaps() async {
    final lat = _currentOffer.pickUpLatitude;
    final lng = _currentOffer.pickUpLongitude;

    // Only open if valid
    if (_hasValidLatLng(lat, lng)) {
      final uri = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=$lat,$lng');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        return;
      }
    }

    // Otherwise show the same clear message used in the placeholder
    final loc = AppLocalizations.of(context);
    _showToast(loc.translate('mapLocationNotAvailable'),
        Theme.of(context).colorScheme.error);
  }

  void _editOffer() async {
    final updatedOffer = await context.push(
      '/add-offers?mode=edit&id=${_currentOffer.id}',
      extra: _currentOffer, // Pass the current offer data
    );

    // If an updated offer was returned, update our state
    if (updatedOffer != null && updatedOffer is OfferModel) {
      // Media removed or added in Edit must not linger from the previous
      // load: the Offer's media is read again from the updated Offer.
      _loadCoordinator.dispose();
      setState(() {
        _currentOffer = updatedOffer;
        _createLoadCoordinator(resolvedOffer: updatedOffer);
        _initializeMediaController();
        // Clear cached widgets to force rebuild with new data
        _cachedMediaGallery = null;
        _cachedMapWidget = null;
      });
      unawaited(_loadCoordinator.load());
    }
    // The land / plot plan may have been added, replaced or removed in the edit.
    if (mounted) unawaited(_planLoader?.load());
  }

  // Show status selector dialog
  void _showStatusSelector() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => PropertyStatusSelector(
        currentStatus: _currentOffer.status,
        allowedStatuses: PropertyStatus.offerStatuses,
        onStatusSelected: (newStatus) {
          _updateOfferStatus(newStatus);
        },
      ),
    );
  }

  // Update offer status
  Future<void> _updateOfferStatus(PropertyStatus newStatus) async {
    if (_currentOffer.id == null) return;

    try {
      final updatedOffer = _currentOffer.copyWith(
        status: newStatus,
        updatedAt: DateTime.now(),
      );

      await _offerService.updateOffer(_currentOffer.id!, updatedOffer);

      setState(() {
        _currentOffer = updatedOffer;
      });

      // final loc = AppLocalizations.of(context);
      // _showToast(
      //   '${loc.translate('offer')} ${loc.translate('statusUpdatedTo')} ${newStatus.displayName}',
      //   Theme.of(context).colorScheme.primary,
      // );
    } catch (e) {
      final loc = AppLocalizations.of(context);
      _showToast(
        '${loc.translate('failedToUpdateStatus')}: ${e.toString()}',
        Theme.of(context).colorScheme.error,
      );
    }
  }

  // Show delete confirmation dialog
  Future<void> _showDeleteConfirmation() async {
    final loc = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFC81E1E),
                size: 28,
              ),
              const SizedBox(width: 12),
              Text(
                loc.translate('deleteOffer'),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                loc.translate('confirmDeleteOffer'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onSurface.withValues(alpha: 0.8),
                    ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE6E6),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFFFFCCCC),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.business_rounded,
                      size: 18,
                      color: Color(0xFFC81E1E),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _currentOffer.offerType == 'rent'
                            ? loc.translate('rentOffer')
                            : loc.translate('saleOffer'),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFFC81E1E),
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            Row(
              children: [
                // Cancel Button
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.surface,
                      foregroundColor: colors.onSurface,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: colors.outline.withValues(alpha: 0.3),
                          width: 1.5,
                        ),
                      ),
                      elevation: 0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: colors.onSurface.withValues(alpha: 0.7),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          loc.translate('cancel'),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: colors.onSurface.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                // Delete Button
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFC81E1E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                      shadowColor:
                          const Color(0xFFC81E1E).withValues(alpha: 0.4),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.delete_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          loc.translate('delete'),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );

    if (confirmed == true && _currentOffer.id != null) {
      await _deleteOffer();
    }
  }

  // Delete the offer and navigate back
  Future<void> _deleteOffer() async {
    final loc = AppLocalizations.of(context);
    try {
      await _offerService.deleteOffer(_currentOffer.id!);

      if (mounted) {
        _showToast(
            loc.translate('offerDeletedSuccessfully'), const Color(0xFF4CAF50));
        // Navigate back to the previous screen
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        _showToast(
            loc.translate('failedToDeleteOffer'), const Color(0xFFC81E1E));
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
