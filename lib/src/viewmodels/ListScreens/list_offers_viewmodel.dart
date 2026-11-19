import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../common/localization/localization_delegate.dart';
import '../../data/models/ScreensModel/offers_model.dart';
import '../../data/models/property_status.dart';
import '../../services/ScreenServices/offer_service.dart';
import 'entity_list_state.dart';

class OffersListViewModel extends ChangeNotifier
    with EntityListState<OfferModel> {
  final OfferService _offerService;

  // Loading state
  bool get isLoading => isInitialLoading;

  // Error state
  String? _error;
  String? get error => _error;

  // Offers list
  List<OfferModel> get offers => entities;
  int get archivedCount =>
      offers.where((offer) => offer.status.isInactive).length;

  // Filter state for offer type
  String? _selectedFilter; // null = all, 'rent' = rent only, 'sell' = sell only
  String? get selectedFilter => _selectedFilter;

  // Filter state for property status - determines which items to show
  bool _showInactiveOnly =
      false; // false = show active only, true = show inactive only
  bool get showInactiveOnly => _showInactiveOnly;

  // Filtered offers based on selected filters
  List<OfferModel> get filteredOffers {
    var filteredList = offers;

    // First filter by status (active/inactive)
    if (_showInactiveOnly) {
      filteredList =
          filteredList.where((offer) => offer.status.isInactive).toList();
    } else {
      filteredList =
          filteredList.where((offer) => offer.status.isActive).toList();
    }

    // Then filter by offer type if selected
    if (_selectedFilter != null) {
      filteredList = filteredList
          .where((offer) => offer.offerType == _selectedFilter)
          .toList();
    }

    return filteredList;
  }

  OffersListViewModel({OfferService? offerService})
      : _offerService = offerService ?? OfferService() {
    // Subscribed once: the source re-reads after every mutation by itself.
    // This account's saved copy shows first, so the list is there offline.
    listenToEntities(_offerService.watchUserOffersLocalFirst());
  }

  @override
  String? entityIdOf(OfferModel item) => item.id;

  @override
  String get debugListName => 'offers';

  // Delete an offer
  Future<void> deleteOffer(String offerId, BuildContext context) async {
    final outcome =
        await deleteEntity(offerId, () => _offerService.deleteOffer(offerId));
    if (!context.mounted) return;
    final loc = AppLocalizations.of(context);
    if (outcome == EntityDeleteOutcome.deleted) {
      _showToast(loc.translate('offerDeletedSuccessfully'), Colors.green);
    } else if (outcome == EntityDeleteOutcome.failed) {
      _showToast(loc.translate('unableToDeleteOffer'), Colors.red);
    }
  }

  void _showToast(String message, Color bgColor) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      timeInSecForIosWeb: 1,
      backgroundColor: bgColor,
      textColor: Colors.white,
    );
  }

  // Toggle filter for offer type
  void toggleFilter(String offerType) {
    if (_selectedFilter == offerType) {
      // If the same filter is selected, clear it (show all)
      _selectedFilter = null;
    } else {
      // Set the new filter
      _selectedFilter = offerType;
    }
    notifyListeners();
  }

  // Clear filter (show all offers)
  void clearFilter() {
    _selectedFilter = null;
    notifyListeners();
  }

  // Toggle between active and inactive items
  void toggleStatusFilter() {
    _showInactiveOnly = !_showInactiveOnly;
    notifyListeners();
  }

  // Update offer status. [translate] gives the messages in the app's
  // language; without it they are in English.
  Future<void> updateOfferStatus(String offerId, PropertyStatus newStatus,
      {String Function(String key)? translate}) async {
    try {
      // Find the offer to update
      final offerIndex = offers.indexWhere((o) => o.id == offerId);
      if (offerIndex == -1) return;

      final offer = offers[offerIndex];
      final updatedOffer = offer.copyWith(
        status: newStatus,
        updatedAt: DateTime.now(),
      );

      // Update the record
      await _offerService.updateOffer(offerId, updatedOffer);

      // The list re-reads by itself after the update; it stays on screen
      // meanwhile.
      _showToast(
          translate == null
              ? 'Offer status updated to ${newStatus.displayName}'
              : translate('offerStatusUpdatedTo')
                  .replaceAll('{status}', translate(newStatus.name)),
          Colors.green);
    } catch (e) {
      _showToast(
          translate == null
              ? 'Unable to update the offer. Please try again.'
              : translate('unableToUpdateOffer'),
          Colors.red);
    }
  }

  // Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    super.dispose();
  }
}
