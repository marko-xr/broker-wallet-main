import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/models/ScreensModel/offers_model.dart';
import '../data/models/ScreensModel/request_model.dart';

/// 🔗 Service for fetching related offers and requests based on phone number matching
/// Used in detail screens to show cross-referenced items
class RelatedItemsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Fetch offers matching the given phone number
  /// Returns a stream of offers where phoneNumber matches
  Stream<List<OfferModel>> getRelatedOffers(String phoneNumber) {
    if (phoneNumber.isEmpty) {
      return Stream.value([]);
    }

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      return Stream.value([]);
    }

    // Clean phone number for matching (remove spaces, dashes, etc.)
    final cleanPhone = _cleanPhoneNumber(phoneNumber);


    return _firestore
        .collection('users')
        .doc(userId)
        .collection('offers')
        .where('phoneNumber', isEqualTo: cleanPhone)
        .limit(10) // Limit to prevent performance issues
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => OfferModel.fromFirestore(doc)).toList();
    });
  }

  /// Fetch requests matching the given phone number
  /// Returns a stream of requests where phoneNumber matches
  Stream<List<RequestModel>> getRelatedRequests(String phoneNumber) {
    if (phoneNumber.isEmpty) {
      return Stream.value([]);
    }

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      return Stream.value([]);
    }

    // Clean phone number for matching
    final cleanPhone = _cleanPhoneNumber(phoneNumber);


    return _firestore
        .collection('users')
        .doc(userId)
        .collection('requests')
        .where('phoneNumber', isEqualTo: cleanPhone)
        .limit(10) // Limit to prevent performance issues
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => RequestModel.fromFirestore(doc))
          .toList();
    });
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

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      return 0;
    }

    final cleanPhone = _cleanPhoneNumber(phoneNumber);

    try {
      final offersSnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('offers')
          .where('phoneNumber', isEqualTo: cleanPhone)
          .count()
          .get();

      final requestsSnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('requests')
          .where('phoneNumber', isEqualTo: cleanPhone)
          .count()
          .get();

      return (offersSnapshot.count ?? 0) + (requestsSnapshot.count ?? 0);
    } catch (e) {
      return 0;
    }
  }
}
