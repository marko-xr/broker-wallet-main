import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../data/models/ScreensModel/offers_model.dart';
import '../../data/models/property_status.dart';
import '../../services/ScreenServices/offer_service.dart';

class OffersListViewModel extends ChangeNotifier {
  final OfferService _offerService = OfferService();

  // Loading state
  bool _isLoading = true;
  bool get isLoading => _isLoading;

  // Error state
  String? _error;
  String? get error => _error;

  // Offers list
  List<OfferModel> _offers = [];
  List<OfferModel> get offers => _offers;

  // Filter state for offer type
  String? _selectedFilter; // null = all, 'rent' = rent only, 'sell' = sell only
  String? get selectedFilter => _selectedFilter;

  // Filter state for property status - determines which items to show
  bool _showInactiveOnly =
      false; // false = show active only, true = show inactive only
  bool get showInactiveOnly => _showInactiveOnly;

  // Stream subscription
  Stream<List<OfferModel>>? _offersStream;
  Stream<List<OfferModel>>? get offersStream => _offersStream;

  // Filtered offers based on selected filters
  List<OfferModel> get filteredOffers {
    var filteredList = _offers;

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

  // Setter for offers (used by the view to update the list)
  set offers(List<OfferModel> newOffers) {
    _offers = newOffers;
  }

  OffersListViewModel() {
    _initializeStream();
  }

  void _initializeStream() {
    _offersStream = _offerService.getUserOffers();
  }

  // Refresh offers
  Future<void> refreshOffers() async {
    // The stream will automatically update when data changes
    _initializeStream();
    notifyListeners();
  }

  // Delete an offer
  Future<void> deleteOffer(String offerId, BuildContext context) async {
    try {
      await _offerService.deleteOffer(offerId);

      if (context.mounted) {
        _showToast('Offer deleted successfully', Colors.green);
        await refreshOffers();
      }
    } catch (e) {
      if (context.mounted) {
        _showToast('Unable to delete the offer. Please try again.', Colors.red);
      }
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

  // Update offer status
  Future<void> updateOfferStatus(
      String offerId, PropertyStatus newStatus) async {
    try {
      // Find the offer to update
      final offerIndex = _offers.indexWhere((o) => o.id == offerId);
      if (offerIndex == -1) return;

      final offer = _offers[offerIndex];
      final updatedOffer = offer.copyWith(
        status: newStatus,
        updatedAt: DateTime.now(),
      );

      // Update in Firestore
      await _offerService.updateOffer(offerId, updatedOffer);

      _showToast(
          'Offer status updated to ${newStatus.displayName}', Colors.green);
      await refreshOffers();
    } catch (e) {
      _showToast('Unable to update the offer. Please try again.', Colors.red);
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
