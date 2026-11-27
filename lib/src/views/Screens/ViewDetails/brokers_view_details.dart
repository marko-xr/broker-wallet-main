import 'package:broker_wallet/src/views/Widgets/favorite_button.dart';
import 'package:broker_wallet/src/services/optimistic_favorites_service.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/brokers_model.dart';
import 'package:broker_wallet/src/services/ScreenServices/broker_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import 'package:broker_wallet/src/services/phone_input_service.dart';
import 'package:broker_wallet/src/services/details_contact_actions.dart';
import 'package:broker_wallet/src/services/share/share_sources.dart';
import 'package:broker_wallet/src/views/Widgets/share_options_dialog.dart';
import 'package:provider/provider.dart';
import 'package:broker_wallet/src/services/related_items_service.dart';
import 'package:broker_wallet/src/widgets/auto_scrolling_related_items_carousel.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';

import 'widgets/details_page.dart';
import 'widgets/details_section.dart';
import 'package:broker_wallet/src/views/Widgets/delete_confirmation_dialog.dart';
import 'package:broker_wallet/src/views/Widgets/field_icons.dart';

class BrokersDetailsView extends StatefulWidget {
  final BrokerModel broker;
  final RelatedItemsService? relatedItemsService;

  const BrokersDetailsView({
    super.key,
    required this.broker,
    this.relatedItemsService,
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
  late final RelatedItemsService _relatedItemsService =
      widget.relatedItemsService ?? RelatedItemsService();
  String? _relatedPhone;
  Stream<List<OfferModel>>? _relatedOffers;
  Stream<List<RequestModel>>? _relatedRequests;

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
    final loc = AppLocalizations.of(context);
    final phone = _currentBroker.phoneNumber;
    final canContact = DetailsContactActions.normalizePhone(phone,
            countryCode: _currentBroker.countryCode) !=
        null;
    return DetailsPage(
      title: loc.translate('brokerDetails'),
      favorite: Consumer<OptimisticFavoritesService>(builder: _buildFavorite),
      onShare: _shareBroker,
      onEdit: _editBroker,
      onDelete: _showDeleteConfirmation,
      deleteLabel: loc.translate('deleteBroker'),
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
    final id = _currentBroker.id;
    if (id == null) {
      return const Icon(Icons.favorite_border, size: 18);
    }
    return OptimizedFavoriteButton(
      size: 18,
      padding: const EdgeInsets.all((kMinInteractiveDimension - 18) / 2),
      isFavorite: favorites.isFavorite(id, 'brokers'),
      isLoading: favorites.isLoading(id, 'brokers'),
      onToggle: () => _toggleFavorite(id, favorites),
    );
  }

  Widget _buildCompactContent(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final name = _currentBroker.name.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DetailsSummary(
          title: name.isEmpty ? loc.translate('brokerNameNotSpecified') : name,
          titleLabel: loc.translate('brokerName'),
          titleMissing: name.isEmpty,
        ),
        const SizedBox(height: DetailsSection.spacing),
        DetailsFields(
          title: loc.translate('contactInformation'),
          rows: [
            DetailsField(
              icon: FieldIcons.phone,
              label: loc.translate('phoneNumber'),
              isMissing: _currentBroker.phoneNumber.trim().isEmpty,
              value: _currentBroker.phoneNumber.trim().isNotEmpty
                  ? PhoneInputService.formatForDisplay(
                      _currentBroker.phoneNumber)
                  : loc.translate('phoneNotAdded'),
              onCopy: _currentBroker.phoneNumber.trim().isNotEmpty
                  ? _copyPhone
                  : null,
            ),
            ...DetailsDates.fields(context,
                createdAt: _currentBroker.createdAt,
                updatedAt: _currentBroker.updatedAt),
          ],
        ),
        if (_currentBroker.notes.isNotEmpty) ...[
          const SizedBox(height: DetailsSection.spacing),
          DetailsNotes(notes: _currentBroker.notes),
        ],
        _buildRelatedItemsCarousel(context),
      ],
    );
  }

  Widget _buildRelatedItemsCarousel(BuildContext context) {
    final phone = _currentBroker.phoneNumber;
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

  Future<void> _openWhatsApp(String phoneNumber) async {
    final loc = AppLocalizations.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    final result = await DetailsContactActions.whatsApp(phoneNumber,
        countryCode: _currentBroker.countryCode);
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
        countryCode: _currentBroker.countryCode);
    if (!mounted || result == ContactLaunchResult.opened) return;
    _showToast(
        loc.translate(result == ContactLaunchResult.invalidPhone
            ? 'phoneNumberNotAvailable'
            : 'unableToMakePhoneCall'),
        errorColor);
  }

  Future<void> _toggleFavorite(
      String id, OptimisticFavoritesService favorites) async {
    final loc = AppLocalizations.of(context);
    // Capture theme colors before async operation
    final primaryColor = Theme.of(context).colorScheme.primary;
    final onSurfaceColor = Theme.of(context).colorScheme.onSurface;
    final errorColor = Theme.of(context).colorScheme.error;

    try {
      final newFavoriteStatus = await favorites.toggleFavorite(id, 'brokers');

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

  void _shareBroker() {
    ShareOptionsDialog.show(
      context,
      source: BrokerShareSource(_currentBroker),
    );
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
    final confirmed = await showDeleteConfirmationDialog(
      context,
      title: loc.translate('deleteBroker'),
      message: loc.translate('deleteBrokerConfirmationMessage'),
      itemIcon: FieldIcons.name,
      itemLabel: _currentBroker.name.isNotEmpty
          ? _currentBroker.name
          : loc.translate('broker'),
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
        _showToast(
            loc.translate('failedToDeleteBroker'), const Color(0xFFC81E1E));
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
