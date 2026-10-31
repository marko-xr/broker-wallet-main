import '../data/models/ScreensModel/offers_model.dart';
import '../data/models/ScreensModel/request_model.dart';
import 'supabase_core_entities_service.dart';

/// 🔗 Service for fetching related offers and requests based on phone number matching
/// Used in detail screens to show cross-referenced items
class RelatedItemsService {
  RelatedItemsService({
    SupabaseCoreEntitiesService? coreEntities,
  }) : _coreEntitiesOverride = coreEntities;

  final SupabaseCoreEntitiesService? _coreEntitiesOverride;
  late final SupabaseCoreEntitiesService _coreEntities =
      _coreEntitiesOverride ?? SupabaseCoreEntitiesService();

  /// Fetch offers matching the given phone number
  /// Returns a stream of offers where phoneNumber matches
  Stream<List<OfferModel>> getRelatedOffers(String phoneNumber) {
    if (phoneNumber.isEmpty) {
      return Stream.value([]);
    }

    final cleanPhone = _cleanPhoneNumber(phoneNumber);
    return _coreEntities.getRelatedOffers(cleanPhone);
  }

  /// Fetch requests matching the given phone number
  /// Returns a stream of requests where phoneNumber matches
  Stream<List<RequestModel>> getRelatedRequests(String phoneNumber) {
    if (phoneNumber.isEmpty) {
      return Stream.value([]);
    }

    final cleanPhone = _cleanPhoneNumber(phoneNumber);
    return _coreEntities.getRelatedRequests(cleanPhone);
  }

  /// Fetch all related items (offers + requests) for a given phone number
  /// Returns a combined stream
  Stream<Map<String, dynamic>> getAllRelatedItems(String phoneNumber) async* {
    if (phoneNumber.isEmpty) {
      yield {'offers': <OfferModel>[], 'requests': <RequestModel>[]};
      return;
    }

    // Use StreamGroup or combine streams manually
    await for (final offers in getRelatedOffers(phoneNumber)) {
      await for (final requests in getRelatedRequests(phoneNumber)) {
        yield {
          'offers': offers,
          'requests': requests,
        };
        break; // Only emit once per offers update
      }
    }
  }

  /// Clean phone number by removing non-numeric characters
  /// Keeps only digits and + sign for country code
  String _cleanPhoneNumber(String phoneNumber) {
    // Remove all characters except digits and +
    return phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
  }

  /// Get total count of related items (offers + requests)
  Future<int> getRelatedItemsCount(String phoneNumber) async {
    if (phoneNumber.isEmpty) {
      return 0;
    }

    final cleanPhone = _cleanPhoneNumber(phoneNumber);
    return _coreEntities.getRelatedItemsCount(cleanPhone);
  }
}
