import 'package:broker_wallet/src/Views/Screens/ViewDetails/widgets/action_decorations.dart';
import 'package:broker_wallet/src/Views/Widgets/favorite_button.dart';
import 'package:broker_wallet/src/services/optimistic_favorites_service.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/brokers_model.dart';
import 'package:broker_wallet/src/services/ScreenServices/broker_service.dart';
import 'package:broker_wallet/src/common/utils/images.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:broker_wallet/src/services/phone_input_service.dart';
import 'package:provider/provider.dart';
import 'package:broker_wallet/src/services/related_items_service.dart';
import 'package:broker_wallet/src/widgets/auto_scrolling_related_items_carousel.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';

class BrokersDetailsView extends StatefulWidget {
  final BrokerModel broker;

  const BrokersDetailsView({
    super.key,
    required this.broker,
  });

  @override
  State<BrokersDetailsView> createState() => _BrokersDetailsViewState();
}

class _BrokersDetailsViewState extends State<BrokersDetailsView>
    with TickerProviderStateMixin {
  late AnimationController _mainAnimationController;
  late AnimationController _fabAnimationController;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _fabAnimation;

  final ScrollController _scrollController = ScrollController();

  // Services
  final BrokerService _brokerService = BrokerService();
  final RelatedItemsService _relatedItemsService = RelatedItemsService();

  // Favorite state - now managed by OptimisticFavoritesService
  late OptimisticFavoritesService _optimisticFavoritesService;

  // Track current broker data (may be updated after edit)
  late BrokerModel _currentBroker;

  @override
  void initState() {
    super.initState();
    _currentBroker = widget.broker;
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
    if (_currentBroker.id != null) {
      await _optimisticFavoritesService.initializeFavoriteStatus(
          _currentBroker.id!, 'brokers');
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
                  if (_currentBroker.id == null) {
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
                      _currentBroker.id!, 'brokers');
                  final isLoading =
                      favoritesService.isLoading(_currentBroker.id!, 'brokers');

                  return OptimizedFavoriteButton(
                    isFavorite: isFavorite,
                    isLoading: isLoading,
                    showBackground: true,
                    size: 18,
                    activeColor: colors.primary,
                    inactiveColor: colors.onSurface,
                    onToggle: () async {
                      // Capture theme colors before async operation
                      final primaryColor =
                          Theme.of(context).colorScheme.primary;
                      final onSurfaceColor =
                          Theme.of(context).colorScheme.onSurface;
                      final errorColor = Theme.of(context).colorScheme.error;

                      try {
                        final newFavoriteStatus = await favoritesService
                            .toggleFavorite(_currentBroker.id!, 'brokers');

                        if (mounted) {
                          _showToast(
                            newFavoriteStatus
                                ? 'Added to favorites'
                                : 'Removed from favorites',
                            newFavoriteStatus ? primaryColor : onSurfaceColor,
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          _showToast('Failed to update favorites', errorColor);
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
            onPressed: _shareBroker,
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
            colors.secondary.withValues(alpha: 0.8),
            colors.tertiary.withValues(alpha: 0.6),
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
                Icons.person_rounded,
                size: 48,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              loc.translate('brokerDetails'),
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
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: Column(
          children: [
            const SizedBox(height: 12),
            _buildHeroCard(context),
            const SizedBox(height: 12),
            _buildQuickInfoGrid(context),
            const SizedBox(height: 12),
            if (_currentBroker.notes.isNotEmpty) ...[
              const SizedBox(height: 4),
              _buildCompactNotesCard(context),
            ],
            // 🔗 Related offers and requests carousel
            _buildRelatedItemsCarousel(context),
          ],
        ),
      ),
    );
  }

  /// 🔗 Build related items carousel showing offers/requests with matching phone
  Widget _buildRelatedItemsCarousel(BuildContext context) {
    if (_currentBroker.phoneNumber.isEmpty) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<List<OfferModel>>(
      stream: _relatedItemsService.getRelatedOffers(_currentBroker.phoneNumber),
      builder: (context, offersSnapshot) {
        return StreamBuilder<List<RequestModel>>(
          stream: _relatedItemsService
              .getRelatedRequests(_currentBroker.phoneNumber),
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
                    loc.translate('broker'),
                    style: texts.labelSmall?.copyWith(
                      color: colors.onSecondary,
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
            const SizedBox(height: 4),

            // Broker name
            Row(
              children: [
                Icon(
                  Icons.person_rounded,
                  color: colors.onPrimaryContainer,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _currentBroker.name.isNotEmpty
                        ? _currentBroker.name
                        : loc.translate('brokerNameNotSpecified'),
                    style: texts.titleLarge?.copyWith(
                      color: colors.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
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

  Widget _buildWhatsAppButton(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final loc = AppLocalizations.of(context);
    final hasPhone = _currentBroker.phoneNumber.isNotEmpty;

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
                _currentBroker.phoneNumber, loc.translate('propertyManager'))
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
    final hasPhone = _currentBroker.phoneNumber.isNotEmpty;

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
            hasPhone ? () => _makePhoneCall(_currentBroker.phoneNumber) : null,
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
                    icon: Icons.person_rounded,
                    title: loc.translate('brokerName'),
                    value: _currentBroker.name.isNotEmpty
                        ? _currentBroker.name
                        : loc.translate('brokerNameNotSpecified'),
                    colors: colors,
                    texts: texts,
                    isEmpty: _currentBroker.name.isEmpty,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildInfoTile(
                    icon: Icons.phone_rounded,
                    title: loc.translate('phoneNumber'),
                    value: _currentBroker.phoneNumber.isNotEmpty
                        ? PhoneInputService.formatForDisplay(
                            _currentBroker.phoneNumber)
                        : loc.translate('phoneNotAdded'),
                    colors: colors,
                    texts: texts,
                    onTap: _currentBroker.phoneNumber.isNotEmpty
                        ? () => _copyPhone()
                        : null,
                    isEmpty: _currentBroker.phoneNumber.isEmpty,
                    isPhone: true,
                  ),
                ),
              ],
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
    bool isEmpty = false,
    bool isPhone = false,
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
                  textDirection: isPhone ? TextDirection.ltr : null,
                  style: texts.bodySmall?.copyWith(
                    fontWeight: isEmpty ? FontWeight.w400 : FontWeight.w600,
                    color: isEmpty
                        ? colors.onErrorContainer.withValues(alpha: 0.8)
                        : colors.onSurface,
                    fontStyle: isEmpty ? FontStyle.italic : FontStyle.normal,
                  ),
                  maxLines: isPhone ? 1 : 1,
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
                _currentBroker.notes,
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

  Widget _buildAnimatedFAB(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final loc = AppLocalizations.of(context);
    final hasPhone = _currentBroker.phoneNumber.isNotEmpty;

    return AnimatedBuilder(
      animation: _fabAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _fabAnimation.value,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.extended(
                heroTag: "edit_broker_fab",
                onPressed: _editBroker,
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
                    ? () => _makePhoneCall(_currentBroker.phoneNumber)
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
  void _shareBroker() {
    final loc = AppLocalizations.of(context);
    final brokerName = _currentBroker.name.isNotEmpty
        ? _currentBroker.name
        : loc.translate('brokerNameNotSpecified');
    final text = '${loc.translate('checkOutThisBroker')}: $brokerName';
    _showToast('${loc.translate('shareFunctionality')}: $text',
        Theme.of(context).colorScheme.primary);
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
    if (_currentBroker.phoneNumber.isEmpty) {
      _showToast(loc.translate('noPhoneNumberToCopy'),
          Theme.of(context).colorScheme.error);
      return;
    }

    final dial = PhoneInputService.formatForDial(_currentBroker.phoneNumber);
    await Clipboard.setData(ClipboardData(
      text: dial,
    ));
    _showToast(loc.translate('phoneNumberCopiedToClipboard'),
        Theme.of(context).colorScheme.primary);
  }

  void _editBroker() async {
    final updatedBroker = await context.push(
      '/add-brokers?mode=edit&id=${_currentBroker.id}',
      extra: _currentBroker, // Pass the current broker data
    );

    // If an updated broker was returned, update our state
    if (updatedBroker != null && updatedBroker is BrokerModel) {
      setState(() {
        _currentBroker = updatedBroker;
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
                loc.translate('deleteBroker'),
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
                loc.translate('deleteBrokerConfirmationMessage'),
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
                      Icons.person_rounded,
                      size: 18,
                      color: Color(0xFFC81E1E),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _currentBroker.name.isNotEmpty
                            ? _currentBroker.name
                            : loc.translate('broker'),
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

    if (confirmed == true && _currentBroker.id != null) {
      await _deleteBroker();
    }
  }

  // Delete the broker and navigate back
  Future<void> _deleteBroker() async {
    final loc = AppLocalizations.of(context);
    try {
      await _brokerService.deleteBroker(_currentBroker.id!);

      if (mounted) {
        _showToast(loc.translate('brokerDeletedSuccessfully'),
            const Color(0xFF4CAF50));
        // Navigate back to the previous screen
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        _showToast('${loc.translate('failedToDeleteBroker')}: ${e.toString()}',
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

// watchmen
// request
