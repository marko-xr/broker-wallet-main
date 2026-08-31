import 'package:broker_wallet/src/Views/Screens/ViewDetails/widgets/action_decorations.dart';
import 'package:broker_wallet/src/Views/Widgets/favorite_button.dart';
import 'package:broker_wallet/src/services/optimistic_favorites_service.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/watchmen_model.dart';
import 'package:broker_wallet/src/services/ScreenServices/watchmen_service.dart';
import 'package:broker_wallet/src/common/utils/images.dart';
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

class WatchmenDetailsView extends StatefulWidget {
  final WatchmenModel watchmen;

  const WatchmenDetailsView({
    super.key,
    required this.watchmen,
  });

  @override
  State<WatchmenDetailsView> createState() => _WatchmenDetailsViewState();
}

class _WatchmenDetailsViewState extends State<WatchmenDetailsView>
    with TickerProviderStateMixin {
  late AnimationController _mainAnimationController;
  late AnimationController _fabAnimationController;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _fabAnimation;

  GoogleMapController? _mapController;
  final ScrollController _scrollController = ScrollController();

  // Services
  final WatchmenService _watchmenService = WatchmenService();
  final RelatedItemsService _relatedItemsService = RelatedItemsService();

  // Favorite state - now managed by OptimisticFavoritesService
  late OptimisticFavoritesService _optimisticFavoritesService;

  // Track current watchmen data (may be updated after edit)
  late WatchmenModel _currentWatchmen;

  // Performance optimization: Cache expensive widgets
  Widget? _cachedMapWidget;

  @override
  void initState() {
    super.initState();
    _currentWatchmen = widget.watchmen;
    _optimisticFavoritesService =
        Provider.of<OptimisticFavoritesService>(context, listen: false);
    _setupAnimations();
    _loadFavoriteStatus();
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

  void _loadFavoriteStatus() async {
    if (_currentWatchmen.id != null) {
      await _optimisticFavoritesService.initializeFavoriteStatus(
          _currentWatchmen.id!, 'watchmen');
    }
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
    final colors = Theme.of(context).colorScheme;

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
      floatingActionButton: _buildAnimatedFAB(context),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildModernAppBar(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;
    final isRTL = Directionality.of(context) == TextDirection.rtl;

    return SliverAppBar(
      expandedHeight: 200,
      floating: false,
      pinned: true,
      stretch: true,
      backgroundColor: colors.surface,
      surfaceTintColor: colors.surface,
      elevation: 0,
      leading: Padding(
        padding: const EdgeInsetsDirectional.only(start: 6, top: 6, bottom: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              margin: const EdgeInsetsDirectional.only(end: 6),
              decoration: BackActionDecoration(colors),
              child: IconButton(
                icon: Icon(
                  isRTL ? Icons.arrow_back_ios_new : Icons.arrow_back_ios_new,
                  color: colors.onSurface,
                  size: 18,
                ),
                onPressed: () => context.pop(),
                padding: EdgeInsets.zero,
              ),
            ),
            Container(
              width: 36,
              height: 36,
              margin: const EdgeInsetsDirectional.only(end: 6),
              child: Consumer<OptimisticFavoritesService>(
                builder: (context, favoritesService, child) {
                  if (_currentWatchmen.id == null) {
                    return Container(
                      decoration: FavoriteActionDecoration(colors),
                      child: Icon(
                        Icons.favorite_border,
                        color: colors.onSurface.withValues(alpha: 0.5),
                        size: 18,
                      ),
                    );
                  }

                  final isFavorite = favoritesService.isFavorite(
                      _currentWatchmen.id!, 'watchmen');
                  final isLoading = favoritesService.isLoading(
                      _currentWatchmen.id!, 'watchmen');

                  return OptimizedFavoriteButton(
                    isFavorite: isFavorite,
                    isLoading: isLoading,
                    showBackground: true,
                    size: 18,
                    activeColor: colors.primary,
                    inactiveColor: colors.onSurface,
                    onToggle: () async {
                      final loc = AppLocalizations.of(context);
                      // Capture theme colors before async operation to avoid accessing disposed context
                      final primaryColor =
                          Theme.of(context).colorScheme.primary;
                      final onSurfaceColor =
                          Theme.of(context).colorScheme.onSurface;
                      final errorColor = Theme.of(context).colorScheme.error;

                      try {
                        final newFavoriteStatus = await favoritesService
                            .toggleFavorite(_currentWatchmen.id!, 'watchmen');

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
                        // Check if widget is still mounted before showing toast
                        if (mounted) {
                          _showToast(
                              loc.translate('failedToUpdateFavoriteStatus'),
                              errorColor);
                        }
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      leadingWidth: 90,
      centerTitle: false,
      actions: [
        Container(
          width: 36,
          height: 36,
          margin: const EdgeInsetsDirectional.fromSTEB(3, 6, 6, 6),
          decoration: DeleteActionDecoration(colors),
          child: IconButton(
            icon: const Icon(
              Icons.delete_outline,
              color: Color(0xFFC81E1E),
              size: 18,
            ),
            onPressed: () => _showDeleteConfirmation(),
            padding: EdgeInsets.zero,
          ),
        ),
        Container(
          width: 36,
          height: 36,
          margin: const EdgeInsetsDirectional.only(end: 6, top: 6, bottom: 6),
          decoration: ShareActionDecoration(colors),
          child: IconButton(
            icon: Icon(Icons.share_outlined, color: colors.onSurface, size: 18),
            onPressed: _shareWatchmen,
            padding: EdgeInsets.zero,
          ),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: RepaintBoundary(
          child: _buildGradientHeader(colors, texts),
        ),
      ),
    );
  }

  Widget _buildGradientHeader(ColorScheme colors, TextTheme texts) {
    final loc = AppLocalizations.of(context);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primary.withValues(alpha: 0.8),
            colors.secondary.withValues(alpha: 0.6),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
              ),
              child: Icon(
                Icons.security_rounded,
                size: 48,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              loc.translate('watchmenDetails'),
              style: texts.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactContent(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;
    final loc = AppLocalizations.of(context);

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: Column(
          children: [
            const SizedBox(height: 12),
            _buildHeroCard(context),
            const SizedBox(height: 12),
            _buildQuickInfoGrid(context),
            const SizedBox(height: 12),
            if (_currentWatchmen.pickUpLatitude != null &&
                _currentWatchmen.pickUpLongitude != null) ...[
              _buildCompactLocationCard(context),
            ] else ...[
              // Show a placeholder when coordinates are not available
              RepaintBoundary(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: colors.shadow.withValues(alpha: 0.08),
                        blurRadius: 16,
                        spreadRadius: 0,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: colors.error.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.location_off_rounded,
                              color: colors.error,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              loc.translate('buildingLocation'),
                              style: texts.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colors.errorContainer.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: colors.error.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.warning_rounded,
                              color: colors.error,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                loc.translate('mapLocationNotAvailable'),
                                style: texts.bodyMedium?.copyWith(
                                  color: colors.onErrorContainer,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (_currentWatchmen.notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildCompactNotesCard(context),
            ],
            _buildRelatedItemsCarousel(context),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;
    final loc = AppLocalizations.of(context);

    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colors.primaryContainer,
              colors.primaryContainer.withValues(alpha: 0.7),
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: colors.primary.withValues(alpha: 0.1),
              blurRadius: 20,
              spreadRadius: 0,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    loc.translate('securityWatchmenCaps'),
                    style: texts.labelSmall?.copyWith(
                      color: colors.onPrimary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const Spacer(),
                _buildCallButton(context),
                const SizedBox(width: 8),
                _buildWhatsAppButton(context),
              ],
            ),
            const SizedBox(height: 8),

            // Watchmen name and building
            Row(
              children: [
                Icon(
                  Icons.security_rounded,
                  color: colors.onPrimaryContainer,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _currentWatchmen.name.isNotEmpty
                        ? _currentWatchmen.name
                        : loc.translate('nameNotSpecified'),
                    style: texts.titleLarge?.copyWith(
                      color: colors.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            Row(
              children: [
                Icon(
                  Icons.apartment_rounded,
                  color: colors.onPrimaryContainer.withValues(alpha: 0.8),
                  size: 16,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _currentWatchmen.buildingName.isNotEmpty
                        ? _currentWatchmen.buildingName
                        : loc.translate('buildingNotSpecified'),
                    style: texts.bodyMedium?.copyWith(
                      color: _currentWatchmen.buildingName.isNotEmpty
                          ? colors.onPrimaryContainer.withValues(alpha: 0.8)
                          : colors.onPrimaryContainer.withValues(alpha: 0.6),
                      fontStyle: _currentWatchmen.buildingName.isEmpty
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWhatsAppButton(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final loc = AppLocalizations.of(context);
    final hasPhone = _currentWatchmen.phoneNumber.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: hasPhone
            ? colors.surface.withValues(alpha: 0.9)
            : colors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        boxShadow: hasPhone
            ? [
                BoxShadow(
                  color: colors.shadow.withValues(alpha: 0.1),
                  blurRadius: 8,
                  spreadRadius: 0,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: IconButton(
        onPressed: hasPhone
            ? () => _openWhatsApp(
                _currentWatchmen.phoneNumber, loc.translate('propertyManager'))
            : null,
        icon: Image.asset(
          hasPhone ? AppImages.whatsapp : AppImages.whatsAppDisable,
          width: 34,
          height: 34,
          color:
              hasPhone ? null : colors.onSurfaceVariant.withValues(alpha: 0.5),
        ),
        constraints: const BoxConstraints(
          minWidth: 44,
          minHeight: 44,
        ),
      ),
    );
  }

  // WhatsApp functionality
  Future<void> _openWhatsApp(String phoneNumber, String managerName) async {
    final loc = AppLocalizations.of(context);
    try {
      // Use PhoneInputService helper to ensure + at start and no spaces
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

  Widget _buildCallButton(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasPhone = _currentWatchmen.phoneNumber.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: hasPhone
            ? colors.surface.withValues(alpha: 0.9)
            : colors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        boxShadow: hasPhone
            ? [
                BoxShadow(
                  color: colors.shadow.withValues(alpha: 0.1),
                  blurRadius: 8,
                  spreadRadius: 0,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: IconButton(
        onPressed: hasPhone
            ? () => _makePhoneCall(_currentWatchmen.phoneNumber)
            : null,
        icon: Icon(
          hasPhone ? Icons.phone_rounded : Icons.phone_disabled_rounded,
          color: hasPhone
              ? colors.primary
              : colors.onSurfaceVariant.withValues(alpha: 0.5),
          size: 28,
        ),
        constraints: const BoxConstraints(
          minWidth: 44,
          minHeight: 44,
        ),
      ),
    );
  }

  Widget _buildQuickInfoGrid(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;
    final loc = AppLocalizations.of(context);

    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: colors.shadow.withValues(alpha: 0.08),
              blurRadius: 16,
              spreadRadius: 0,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _buildInfoTile(
                    icon: Icons.security_rounded,
                    title: loc.translate('watchmenName'),
                    value: _currentWatchmen.name.isNotEmpty
                        ? _currentWatchmen.name
                        : loc.translate('nameNotProvided'),
                    colors: colors,
                    texts: texts,
                    isEmpty: _currentWatchmen.name.isEmpty,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildInfoTile(
                    icon: Icons.phone_rounded,
                    title: loc.translate('phoneNumber'),
                    value: _currentWatchmen.phoneNumber.isNotEmpty
                        ? PhoneInputService.formatForDisplay(
                            _currentWatchmen.phoneNumber)
                        : loc.translate('phoneNotAdded'),
                    colors: colors,
                    texts: texts,
                    onTap: _currentWatchmen.phoneNumber.isNotEmpty
                        ? () => _copyPhone()
                        : null,
                    isEmpty: _currentWatchmen.phoneNumber.isEmpty,
                    isPhone: true, // NEW
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoTile(
              icon: Icons.apartment_rounded,
              title: loc.translate('buildingName'),
              value: _currentWatchmen.buildingName.isNotEmpty
                  ? _currentWatchmen.buildingName
                  : loc.translate('buildingNameNotSpecified'),
              colors: colors,
              texts: texts,
              fullWidth: true,
              isEmpty: _currentWatchmen.buildingName.isEmpty,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    required String value,
    required ColorScheme colors,
    required TextTheme texts,
    VoidCallback? onTap,
    bool fullWidth = false,
    bool isEmpty = false,
    bool isPhone = false, // NEW param
  }) {
    final widget = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isEmpty
            ? colors.errorContainer.withValues(alpha: 0.3)
            : colors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isEmpty
              ? colors.error.withValues(alpha: 0.2)
              : colors.outline.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isEmpty
                  ? colors.error.withValues(alpha: 0.1)
                  : colors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isEmpty ? Icons.warning_rounded : icon,
              size: 16,
              color: isEmpty ? colors.error : colors.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: texts.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 2),

                // Here we render the value. If it's a phone, force LTR direction.
                Text(
                  value,
                  textDirection: isPhone ? TextDirection.ltr : null,
                  style: texts.bodySmall?.copyWith(
                    fontWeight: isEmpty ? FontWeight.w400 : FontWeight.w600,
                    color: isEmpty
                        ? colors.onErrorContainer.withValues(alpha: 0.8)
                        : colors.onSurface,
                    fontStyle: isEmpty ? FontStyle.italic : FontStyle.normal,
                  ),
                  maxLines: fullWidth ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (onTap != null && !isEmpty) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.copy_rounded,
              size: 14,
              color: colors.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );

    if (onTap != null && !isEmpty) {
      return GestureDetector(
        onTap: onTap,
        child: widget,
      );
    }

    return widget;
  }

  Widget _buildCompactLocationCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;
    final loc = AppLocalizations.of(context);

    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: colors.shadow.withValues(alpha: 0.08),
              blurRadius: 16,
              spreadRadius: 0,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.location_on_rounded,
                    color: colors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    loc.translate('buildingLocation'),
                    style: texts.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _openInMaps,
                  icon: Icon(
                    Icons.open_in_new_rounded,
                    size: 16,
                    color: colors.primary,
                  ),
                  label: Text(
                    loc.translate('maps'),
                    style: texts.bodySmall?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_currentWatchmen.pickUpLocation.isNotEmpty) ...[
              Text(
                _currentWatchmen.pickUpLocation,
                style: texts.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ] else ...[
              Text(
                loc.translate('specificLocationNotProvided'),
                style: texts.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant.withValues(alpha: 0.7),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 12),
            _buildCachedMiniMap(context),
          ],
        ),
      ),
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
                _currentWatchmen.pickUpLatitude!,
                _currentWatchmen.pickUpLongitude!,
              ),
              zoom: 15,
            ),
            markers: {
              Marker(
                markerId: const MarkerId('pickup_location'),
                position: LatLng(
                  _currentWatchmen.pickUpLatitude!,
                  _currentWatchmen.pickUpLongitude!,
                ),
                infoWindow: InfoWindow(
                  title: _currentWatchmen.pickUpLocation,
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

  Widget _buildCompactNotesCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;
    final loc = AppLocalizations.of(context);

    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: colors.shadow.withValues(alpha: 0.08),
              blurRadius: 16,
              spreadRadius: 0,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.secondary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.note_alt_rounded,
                    color: colors.secondary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  loc.translate('notes'),
                  style: texts.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colors.outline.withValues(alpha: 0.08),
                ),
              ),
              child: Text(
                _currentWatchmen.notes,
                style: texts.bodyMedium?.copyWith(
                  height: 1.5,
                  color: colors.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRelatedItemsCarousel(BuildContext context) {
    if (_currentWatchmen.phoneNumber.isEmpty) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<List<OfferModel>>(
      stream:
          _relatedItemsService.getRelatedOffers(_currentWatchmen.phoneNumber),
      builder: (context, offersSnapshot) {
        return StreamBuilder<List<RequestModel>>(
          stream: _relatedItemsService
              .getRelatedRequests(_currentWatchmen.phoneNumber),
          builder: (context, requestsSnapshot) {
            final offers = offersSnapshot.data ?? [];
            final requests = requestsSnapshot.data ?? [];
            final totalItems = offers.length + requests.length;

            if (totalItems == 0) {
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

  Widget _buildAnimatedFAB(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final loc = AppLocalizations.of(context);
    final hasPhone = _currentWatchmen.phoneNumber.isNotEmpty;

    return AnimatedBuilder(
      animation: _fabAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _fabAnimation.value,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.extended(
                heroTag: "edit_watchmen_fab",
                onPressed: _editWatchmen,
                icon: const Icon(Icons.edit_rounded, size: 20),
                label: Text(
                  loc.translate('edit'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
                elevation: 8,
                extendedPadding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              const SizedBox(height: 16),
              FloatingActionButton(
                heroTag: "call_phone_fab",
                onPressed: hasPhone
                    ? () => _makePhoneCall(_currentWatchmen.phoneNumber)
                    : null,
                backgroundColor: hasPhone
                    ? colors.secondary
                    : colors.surfaceContainerHighest,
                foregroundColor:
                    hasPhone ? colors.onSecondary : colors.onSurfaceVariant,
                elevation: hasPhone ? 8 : 2,
                child: Icon(
                  hasPhone ? Icons.phone_rounded : Icons.phone_disabled_rounded,
                  size: 24,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Action methods
  void _shareWatchmen() {
    final loc = AppLocalizations.of(context);
    // Capture theme color before potential operations
    final primaryColor = Theme.of(context).colorScheme.primary;

    final text =
        '${loc.translate('checkOutThisWatchmenContact')}: ${_currentWatchmen.name} ${loc.translate('at')} ${_currentWatchmen.buildingName}';
    _showToast('${loc.translate('shareFunctionality')}: $text', primaryColor);
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final loc = AppLocalizations.of(context);
    // Capture theme color before async operation
    final errorColor = Theme.of(context).colorScheme.error;

    if (phoneNumber.isEmpty) {
      _showToast(loc.translate('phoneNumberNotAvailable'), errorColor);
      return;
    }

    final dial = PhoneInputService.formatForDial(phoneNumber);
    final Uri phoneUri = Uri(scheme: 'tel', path: dial);
    try {
      await launchUrl(phoneUri, mode: LaunchMode.platformDefault);
    } on PlatformException catch (e) {
      debugPrint('Failed to open dialer: ${e.message}');
      if (mounted) {
        _showToast(loc.translate('unableToMakePhoneCall'), errorColor);
      }
    }
  }

  Future<void> _copyPhone() async {
    final loc = AppLocalizations.of(context);
    // Capture theme colors before potential async operations
    final errorColor = Theme.of(context).colorScheme.error;
    final primaryColor = Theme.of(context).colorScheme.primary;

    if (_currentWatchmen.phoneNumber.isEmpty) {
      _showToast(loc.translate('noPhoneNumberToCopy'), errorColor);
      return;
    }

    final dial = PhoneInputService.formatForDial(_currentWatchmen.phoneNumber);
    await Clipboard.setData(ClipboardData(text: dial));
    _showToast(loc.translate('phoneNumberCopiedToClipboard'), primaryColor);
  }

  void _openInMaps() async {
    final lat = _currentWatchmen.pickUpLatitude;
    final lng = _currentWatchmen.pickUpLongitude;
    if (lat != null && lng != null) {
      final uri = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=$lat,$lng');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    }
  }

  void _editWatchmen() async {
    // Navigate to edit watchmen screen with data pre-filled
    final updatedWatchmen = await context.push(
      '/add-watchmen?mode=edit&id=${_currentWatchmen.id}',
      extra: _currentWatchmen, // Pass the current watchmen data
    );

    // If an updated watchmen was returned, update our state
    if (updatedWatchmen != null && updatedWatchmen is WatchmenModel) {
      setState(() {
        _currentWatchmen = updatedWatchmen;
        // Clear cached widgets to force rebuild with new data
        _cachedMapWidget = null;
      });
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
                loc.translate('deleteWatchmen'),
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
                loc.translate('deleteWatchmenConfirmationMessage'),
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
                      Icons.security_rounded,
                      size: 18,
                      color: Color(0xFFC81E1E),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _currentWatchmen.name.isNotEmpty
                            ? _currentWatchmen.name
                            : loc.translate('watchmenContact'),
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

    if (confirmed == true && _currentWatchmen.id != null) {
      await _deleteWatchmen();
    }
  }

  // Delete the watchmen and navigate back
  Future<void> _deleteWatchmen() async {
    final loc = AppLocalizations.of(context);

    try {
      await _watchmenService.deleteWatchmen(_currentWatchmen.id!);

      if (mounted) {
        _showToast(loc.translate('watchmenDeletedSuccessfully'),
            const Color(0xFF4CAF50));
        // Navigate back to the previous screen
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        _showToast(
            '${loc.translate('failedToDeleteWatchmen')}: ${e.toString()}',
            const Color(0xFFC81E1E));
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
