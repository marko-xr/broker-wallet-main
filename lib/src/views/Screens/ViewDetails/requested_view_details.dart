import 'dart:ui' as ui;

import 'package:broker_wallet/src/Views/Screens/ViewDetails/widgets/request_share_options_dialog.dart';
import 'package:broker_wallet/src/Views/Widgets/property_status_indicator.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';
import 'package:broker_wallet/src/data/models/property_status.dart';
import 'package:broker_wallet/src/services/ScreenServices/request_service.dart';
import 'package:broker_wallet/src/services/optimistic_favorites_service.dart';
import 'package:broker_wallet/src/Views/Widgets/favorite_button.dart';
import 'package:broker_wallet/src/common/utils/images.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import 'package:broker_wallet/src/services/phone_input_service.dart';
import 'package:intl/intl.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';

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
    final isRent = _currentRequest.requestType == 'rent';
    final isRTL = Directionality.of(context) == ui.TextDirection.rtl;

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
              decoration: _BackActionDecoration(colors),
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
                  final requestId = _currentRequest.id;

                  if (requestId == null) {
                    return Container(
                      decoration: _FavoriteActionDecoration(colors),
                      child: Icon(
                        Icons.favorite_border,
                        color: colors.onSurface.withValues(alpha: 0.5),
                        size: 18,
                      ),
                    );
                  }

                  return OptimizedFavoriteButton(
                    isFavorite: favoritesService.isRequestFavorite(requestId),
                    isLoading: favoritesService.isRequestLoading(requestId),
                    onToggle: () => _toggleFavorite(),
                    size: 18,
                    activeColor: colors.primary,
                    inactiveColor: colors.onSurface,
                    showBackground: true,
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
          decoration: _DeleteActionDecoration(colors),
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
          decoration: _ShareActionDecoration(colors),
          child: IconButton(
            icon: Icon(Icons.share_outlined, color: colors.onSurface, size: 18),
            onPressed: _shareRequest,
            padding: EdgeInsets.zero,
          ),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: RepaintBoundary(
          child: _buildGradientHeader(context, isRent, colors, texts),
        ),
      ),
    );
  }

  Widget _buildGradientHeader(
      BuildContext context, bool isRent, ColorScheme colors, TextTheme texts) {
    final loc = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isRent
              ? [
                  colors.primary.withValues(alpha: 0.8),
                  colors.secondary.withValues(alpha: 0.6),
                ]
              : [
                  colors.tertiary.withValues(alpha: 0.8),
                  colors.error.withValues(alpha: 0.6),
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
                isRent ? Icons.search_rounded : Icons.business_center_rounded,
                size: 48,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isRent
                  ? loc.translate('rentRequest')
                  : loc.translate('saleRequest'),
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
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        child: Column(
          children: [
            const SizedBox(height: 12),
            _buildHeroCard(context),
            const SizedBox(height: 12),
            _buildQuickInfoGrid(context),
            const SizedBox(height: 12),
            if (_currentRequest.notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildCompactNotesCard(context),
            ],
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
    final isRent = _currentRequest.requestType == 'rent';

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
                    color: isRent ? colors.primary : colors.tertiary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isRent
                        ? loc.translate('lookingToRent')
                        : loc.translate('lookingToBuy'),
                    style: texts.labelSmall?.copyWith(
                      color: isRent ? colors.onPrimary : colors.onTertiary,
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

            // Property type and location
            Row(
              children: [
                Icon(
                  _getPropertyIcon(),
                  color: colors.onPrimaryContainer,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _getPropertyDisplayText().isNotEmpty
                        ? _getPropertyDisplayText()
                        : loc.translate('propertyTypeNotSpecified'),
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
                  Icons.location_on_rounded,
                  color: colors.onPrimaryContainer.withValues(alpha: 0.8),
                  size: 16,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _getLocationText().isNotEmpty
                        ? _getLocationText()
                        : loc.translate('locationNotSpecified'),
                    style: texts.bodyMedium?.copyWith(
                      color: _getLocationText().isNotEmpty
                          ? colors.onPrimaryContainer.withValues(alpha: 0.8)
                          : colors.onPrimaryContainer.withValues(alpha: 0.6),
                      fontStyle: _getLocationText().isEmpty
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Price range
            _buildPriceDisplay(context),

            const SizedBox(height: 12),

            // Square footage
            _buildSquareFootageDisplay(context),

            // Property details (rooms, baths) if applicable
            if (_shouldShowRoomsAndBaths()) ...[
              const SizedBox(height: 16),
              _buildPropertyStats(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWhatsAppButton(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final loc = AppLocalizations.of(context);
    final hasPhone = _currentRequest.phoneNumber.isNotEmpty;

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
                _currentRequest.phoneNumber, loc.translate('propertyManager'))
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
    final hasPhone = _currentRequest.phoneNumber.isNotEmpty;

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
        onPressed:
            hasPhone ? () => _makePhoneCall(_currentRequest.phoneNumber) : null,
        icon: Icon(
          hasPhone ? Icons.phone_rounded : Icons.phone_disabled_rounded,
          color: hasPhone
              ? colors.primary
              : colors.onSurfaceVariant.withValues(alpha: 0.5),
          size: 30,
        ),
        constraints: const BoxConstraints(
          minWidth: 44,
          minHeight: 44,
        ),
      ),
    );
  }

  Widget _buildPriceDisplay(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;
    final loc = AppLocalizations.of(context);

    // Check if both prices are empty
    final bool hasPricing = _currentRequest.minPrice.isNotEmpty ||
        _currentRequest.maxPrice.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: hasPricing
            ? colors.surface.withValues(alpha: 0.9)
            : colors.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasPricing
              ? colors.outline.withValues(alpha: 0.1)
              : colors.error.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasPricing ? Icons.payments_rounded : Icons.warning_rounded,
            color: hasPricing ? colors.primary : colors.error,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasPricing) ...[
                  // Show price when available
                  if (_currentRequest.minPrice.isNotEmpty &&
                      _currentRequest.maxPrice.isNotEmpty) ...[
                    Text(
                      '${_currentRequest.minPrice} - ${_currentRequest.maxPrice} AED',
                      style: texts.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colors.primary,
                      ),
                    ),
                  ] else if (_currentRequest.minPrice.isNotEmpty) ...[
                    Text(
                      'From ${_currentRequest.minPrice} AED',
                      style: texts.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colors.primary,
                      ),
                    ),
                  ] else if (_currentRequest.maxPrice.isNotEmpty) ...[
                    Text(
                      'Up to ${_currentRequest.maxPrice} AED',
                      style: texts.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colors.primary,
                      ),
                    ),
                  ],
                  Text(
                    loc.translate('priceRange'),
                    style: texts.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ] else ...[
                  // Show empty state when no pricing
                  Text(
                    loc.translate('budgetNotSpecified'),
                    style: texts.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.onErrorContainer,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSquareFootageDisplay(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;
    final loc = AppLocalizations.of(context);

    final String value = _currentRequest.squareFootage.trim();
    final bool hasFootage = value.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: hasFootage
            ? colors.surface.withValues(alpha: 0.9)
            : colors.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasFootage
              ? colors.outline.withValues(alpha: 0.1)
              : colors.error.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasFootage ? Icons.square_foot : Icons.info_outline,
            color: hasFootage ? colors.primary : colors.error,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasFootage
                      ? '${_formatSquareFootage(value)} ${loc.translate('squareFootageUnit')}'
                      : loc.translate('squareFootageNotSpecified'),
                  style: texts.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: hasFootage ? colors.primary : Colors.white,
                    fontStyle: hasFootage ? FontStyle.normal : FontStyle.italic,
                  ),
                ),
                if (hasFootage)
                  Text(
                    loc.translate('squareFootage'),
                    style: texts.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
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

    return Row(
      children: [
        Expanded(
          child: _buildStatItem(
            Icons.bed_rounded,
            _currentRequest.rooms.toString(),
            loc.translate('rooms'),
            colors,
            texts,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatItem(
            Icons.bathtub_rounded,
            _currentRequest.bathrooms.toString(),
            loc.translate('bathrooms'),
            colors,
            texts,
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label,
      ColorScheme colors, TextTheme texts) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colors.outline.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: colors.primary),
          const SizedBox(width: 6),
          Column(
            children: [
              Text(
                value,
                style: texts.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colors.onSurface,
                ),
              ),
              Text(
                label,
                style: texts.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
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
                    icon: Icons.location_city_rounded,
                    title: loc.translate('city'),
                    value: _currentRequest.selectedCity.isNotEmpty
                        ? _getLocalizedCityName(_currentRequest.selectedCity)
                        : loc.translate('cityNotSpecified'),
                    colors: colors,
                    texts: texts,
                    isEmpty: _currentRequest.selectedCity.isEmpty,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildInfoTile(
                    icon: Icons.phone_rounded,
                    title: loc.translate('phoneNumber'),
                    value: _currentRequest.phoneNumber.isNotEmpty
                        ? PhoneInputService.formatForDisplay(
                            _currentRequest.phoneNumber)
                        : loc.translate('phoneNotAdded'),
                    colors: colors,
                    texts: texts,
                    onTap: _currentRequest.phoneNumber.isNotEmpty
                        ? () => _copyPhone()
                        : null,
                    isEmpty: _currentRequest.phoneNumber.isEmpty,
                    isPhone: true, // NEW
                  ),
                ),
              ],
            ),
            if (_currentRequest.selectedAreas.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildInfoTile(
                icon: Icons.place_rounded,
                title: loc.translate('areas'),
                value: _getLocalizedAreasText(_currentRequest.selectedAreas),
                colors: colors,
                texts: texts,
                fullWidth: true,
              ),
            ] else ...[
              const SizedBox(height: 12),
              _buildInfoTile(
                icon: Icons.place_rounded,
                title: loc.translate('areas'),
                value: loc.translate('areasNotSpecified'),
                colors: colors,
                texts: texts,
                fullWidth: true,
                isEmpty: true,
              ),
            ],
            if (_currentRequest.location.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildInfoTile(
                icon: Icons.location_on_rounded,
                title: loc.translate('specificLocation'),
                value: _currentRequest.location,
                colors: colors,
                texts: texts,
                fullWidth: true,
              ),
            ],
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
                Text(
                  value,
                  textDirection: isPhone ? ui.TextDirection.ltr : null,
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
                _currentRequest.notes,
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

  Widget _buildAnimatedFAB(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final loc = AppLocalizations.of(context);

    return AnimatedBuilder(
      animation: _fabAnimation,
      builder: (context, child) {
        final statusColor = _statusColor(_currentRequest.status);
        final statusIcon = _statusIcon(_currentRequest.status);
        final statusLabel = _getLocalizedStatusLabel();
        final canUpdateStatus = _currentRequest.id != null;

        return Transform.scale(
          scale: _fabAnimation.value,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FloatingActionButton.extended(
                heroTag: "status_request_fab",
                onPressed: canUpdateStatus ? () => _showStatusSelector() : null,
                icon: Icon(statusIcon, size: 20),
                label: Text(
                  statusLabel,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                backgroundColor: canUpdateStatus
                    ? statusColor.withValues(alpha: 0.15)
                    : colors.surfaceContainerHighest.withValues(alpha: 0.7),
                foregroundColor:
                    canUpdateStatus ? statusColor : colors.onSurfaceVariant,
                elevation: canUpdateStatus ? 8 : 0,
              ),
              const SizedBox(height: 16),
              FloatingActionButton.extended(
                heroTag: "edit_request_fab",
                onPressed: _editRequest,
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
            ],
          ),
        );
      },
    );
  }

  // Helper methods
  String _getLocalizedStatusLabel() {
    final loc = AppLocalizations.of(context);
    final statusKey = _currentRequest.status.name;
    final translated = loc.translate(statusKey);

    if (translated.startsWith('** ')) {
      return _currentRequest.status.displayName;
    }

    return translated;
  }

  Color _statusColor(PropertyStatus status) {
    return Color(
        int.parse(status.colorCode.substring(1), radix: 16) + 0xFF000000);
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

  IconData _getPropertyIcon() {
    switch (_currentRequest.specificPropertyType.toLowerCase()) {
      case 'villa':
        return Icons.home_rounded;
      case 'apartment':
        return Icons.apartment_rounded;
      case 'studio':
        return Icons.meeting_room_rounded;
      case 'office space':
        return Icons.business_rounded;
      case 'shop':
        return Icons.store_rounded;
      case 'warehouse':
        return Icons.warehouse_rounded;
      default:
        return Icons.search_rounded;
    }
  }

  String _getPropertyDisplayText() {
    if (_currentRequest.specificPropertyType.isEmpty) {
      return '';
    }

    String propertyText =
        _getLocalizedSpecificType(_currentRequest.specificPropertyType);
    if (_currentRequest.propertyType != null &&
        _currentRequest.propertyType!.isNotEmpty) {
      String localizedPropertyType =
          _getLocalizedPropertyType(_currentRequest.propertyType!);
      propertyText = '$propertyText - $localizedPropertyType';
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
    final authVM = Provider.of<AuthViewModel>(context, listen: false);
    final userPhoneNumber = authVM.currentUser?.phoneNumber ?? '';

    showDialog(
      context: context,
      builder: (context) => RequestShareOptionsDialog(
        request: _currentRequest,
        userPhoneNumber: userPhoneNumber,
      ),
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => PropertyStatusSelector(
        currentStatus: _currentRequest.status,
        allowedStatuses: PropertyStatus.requestStatuses,
        onStatusSelected: (newStatus) {
          _updateRequestStatus(newStatus);
        },
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

      setState(() {
        _currentRequest = updatedRequest;
      });

      final loc = AppLocalizations.of(context);
      _showToast(
        '${loc.translate('request')} ${loc.translate('statusUpdatedTo')} ${newStatus.displayName}',
        Theme.of(context).colorScheme.primary,
      );
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
                loc.translate('deleteRequest'),
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
                loc.translate('deleteRequestConfirmationMessage'),
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
                      Icons.search_rounded,
                      size: 18,
                      color: Color(0xFFC81E1E),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _currentRequest.requestType == 'rent'
                            ? loc.translate('rentRequest')
                            : loc.translate('saleRequest'),
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

class _BaseActionDecoration extends BoxDecoration {
  _BaseActionDecoration({
    required Color backgroundColor,
    required Color shadowColor,
  }) : super(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: shadowColor,
              blurRadius: 8,
              spreadRadius: 0,
              offset: const Offset(0, 1),
            ),
          ],
        );
}

class _BackActionDecoration extends _BaseActionDecoration {
  _BackActionDecoration(ColorScheme colors)
      : super(
          backgroundColor: colors.surface.withValues(alpha: 0.95),
          shadowColor: colors.shadow.withValues(alpha: 0.12),
        );
}

class _FavoriteActionDecoration extends _BaseActionDecoration {
  _FavoriteActionDecoration(ColorScheme colors)
      : super(
          backgroundColor: colors.surface.withValues(alpha: 0.95),
          shadowColor: colors.shadow.withValues(alpha: 0.12),
        );
}

class _ShareActionDecoration extends _BaseActionDecoration {
  _ShareActionDecoration(ColorScheme colors)
      : super(
          backgroundColor: colors.surface.withValues(alpha: 0.95),
          shadowColor: colors.shadow.withValues(alpha: 0.12),
        );
}

class _DeleteActionDecoration extends _BaseActionDecoration {
  _DeleteActionDecoration(ColorScheme colors)
      : super(
          backgroundColor: const Color(0xFFC81E1E).withValues(alpha: 0.1),
          shadowColor: colors.shadow.withValues(alpha: 0.12),
        );
}
