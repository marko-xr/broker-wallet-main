import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:broker_wallet/src/repositories/property_repository.dart';
import 'package:broker_wallet/src/data/models/property.dart';
import 'dart:async';

/// Firestore implementation of PropertyRepository
/// Contains all Firestore-specific property data operations
class FirestorePropertyRepository implements PropertyRepository {
  // Use lazy getter to avoid accessing Firebase before initialization
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  static const String _propertiesCollection = 'properties';
  static const String _favoritesCollection = 'user_favorites';

  @override
  Future<List<Property>> getAllProperties() async {
    try {
      // Try cache first for offline support
      QuerySnapshot querySnapshot;
      try {
        querySnapshot = await _firestore
            .collection(_propertiesCollection)
            .get(const GetOptions(source: Source.cache));

        if (querySnapshot.docs.isNotEmpty) {
          return querySnapshot.docs
              .map((doc) =>
                  Property.fromMap(doc.id, doc.data() as Map<String, dynamic>))
              .toList();
        }
      } catch (e) {
        // Cache read failed for properties, will fallback to server (log removed)
      }

      // Fallback to server with timeout
      querySnapshot = await _firestore
          .collection(_propertiesCollection)
          .get(const GetOptions(source: Source.server))
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw TimeoutException(
                'getAllProperties timeout', const Duration(seconds: 10)),
          );

      return querySnapshot.docs
          .map((doc) =>
              Property.fromMap(doc.id, doc.data() as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (e is TimeoutException) {
        // getAllProperties timeout - returning empty list for offline (log removed)
        return [];
      }
      throw Exception('Failed to get properties: $e');
    }
  }

  @override
  Future<List<Property>> getPropertiesByCategory(
      PropertyCategory category) async {
    try {
      final querySnapshot = await _firestore
          .collection(_propertiesCollection)
          .where('category', isEqualTo: category.toString().split('.').last)
          .get();

      return querySnapshot.docs
          .map((doc) => Property.fromMap(doc.id, doc.data()))
          .toList();
    } catch (e) {
      throw Exception('Failed to get properties by category: $e');
    }
  }

  @override
  Future<Property?> getPropertyById(String id) async {
    try {
      // Try cache first
      DocumentSnapshot doc;
      try {
        doc = await _firestore
            .collection(_propertiesCollection)
            .doc(id)
            .get(const GetOptions(source: Source.cache));

        if (doc.exists && doc.data() != null) {
          return Property.fromMap(doc.id, doc.data() as Map<String, dynamic>);
        }
      } catch (e) {
        // Cache read failed for property $id, will fallback to server (log removed)
      }

      // Fallback to server with timeout
      doc = await _firestore
          .collection(_propertiesCollection)
          .doc(id)
          .get(const GetOptions(source: Source.server))
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw TimeoutException(
                'getPropertyById timeout', const Duration(seconds: 5)),
          );

      if (doc.exists && doc.data() != null) {
        return Property.fromMap(doc.id, doc.data() as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      if (e is TimeoutException) {
        // getPropertyById timeout for $id - returning null (log removed)
        return null;
      }
      throw Exception('Failed to get property: $e');
    }
  }

  @override
  Future<String> createProperty(Property property) async {
    try {
      final docRef = await _firestore
          .collection(_propertiesCollection)
          .add(property.toMap());

      return docRef.id;
    } catch (e) {
      throw Exception('Failed to create property: $e');
    }
  }

  @override
  Future<void> updateProperty(Property property) async {
    try {
      await _firestore
          .collection(_propertiesCollection)
          .doc(property.id)
          .update(property.toMap());
    } catch (e) {
      throw Exception('Failed to update property: $e');
    }
  }

  @override
  Future<void> deleteProperty(String id) async {
    try {
      await _firestore.collection(_propertiesCollection).doc(id).delete();
    } catch (e) {
      throw Exception('Failed to delete property: $e');
    }
  }

  @override
  Future<List<Property>> searchProperties({
    String? query,
    PropertyCategory? category,
    double? minPrice,
    double? maxPrice,
    String? location,
  }) async {
    try {
      Query firestoreQuery = _firestore.collection(_propertiesCollection);

      // Apply filters
      if (category != null) {
        firestoreQuery = firestoreQuery.where('category',
            isEqualTo: category.toString().split('.').last);
      }

      if (minPrice != null) {
        firestoreQuery =
            firestoreQuery.where('price', isGreaterThanOrEqualTo: minPrice);
      }

      if (maxPrice != null) {
        firestoreQuery =
            firestoreQuery.where('price', isLessThanOrEqualTo: maxPrice);
      }

      final querySnapshot = await firestoreQuery.get();

      List<Property> properties = querySnapshot.docs
          .map((doc) =>
              Property.fromMap(doc.id, doc.data() as Map<String, dynamic>))
          .toList();

      // Apply text search on client side (Firestore doesn't have full-text search)
      if (query != null && query.isNotEmpty) {
        final searchQuery = query.toLowerCase();
        properties = properties.where((property) {
          // Assuming Property has searchable fields like title, description, etc.
          // You'll need to implement this based on your Property model
          return property.toString().toLowerCase().contains(searchQuery);
        }).toList();
      }

      return properties;
    } catch (e) {
      throw Exception('Failed to search properties: $e');
    }
  }

  @override
  Future<List<Property>> getUserProperties(String userId) async {
    try {
      final querySnapshot = await _firestore
          .collection(_propertiesCollection)
          .where('ownerId', isEqualTo: userId)
          .get();

      return querySnapshot.docs
          .map((doc) => Property.fromMap(doc.id, doc.data()))
          .toList();
    } catch (e) {
      throw Exception('Failed to get user properties: $e');
    }
  }

  @override
  Future<List<Property>> getUserFavorites(String userId) async {
    try {
      final favoritesDoc =
          await _firestore.collection(_favoritesCollection).doc(userId).get();

      if (!favoritesDoc.exists) {
        return [];
      }

      final favoriteIds =
          List<String>.from(favoritesDoc.data()?['propertyIds'] ?? []);

      if (favoriteIds.isEmpty) {
        return [];
      }

      // Firestore 'in' queries are limited to 10 items, so we need to batch
      final List<Property> favorites = [];
      const int batchSize = 10;

      for (int i = 0; i < favoriteIds.length; i += batchSize) {
        final batch = favoriteIds.skip(i).take(batchSize).toList();

        final querySnapshot = await _firestore
            .collection(_propertiesCollection)
            .where(FieldPath.documentId, whereIn: batch)
            .get();

        favorites.addAll(
          querySnapshot.docs
              .map((doc) => Property.fromMap(doc.id, doc.data()))
              .toList(),
        );
      }

      return favorites;
    } catch (e) {
      throw Exception('Failed to get user favorites: $e');
    }
  }

  @override
  Future<void> addToFavorites(String userId, String propertyId) async {
    try {
      await _firestore.collection(_favoritesCollection).doc(userId).set({
        'propertyIds': FieldValue.arrayUnion([propertyId]),
      }, SetOptions(merge: true));
    } catch (e) {
      throw Exception('Failed to add to favorites: $e');
    }
  }

  @override
  Future<void> removeFromFavorites(String userId, String propertyId) async {
    try {
      await _firestore.collection(_favoritesCollection).doc(userId).update({
        'propertyIds': FieldValue.arrayRemove([propertyId]),
      });
    } catch (e) {
      throw Exception('Failed to remove from favorites: $e');
    }
  }

  @override
  Stream<List<Property>> get propertiesStream {
    try {
      return _firestore.collection(_propertiesCollection).snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => Property.fromMap(doc.id, doc.data()))
              .toList());
    } catch (e) {
      throw Exception('Failed to get properties stream: $e');
    }
  }

  @override
  Stream<List<Property>> getUserFavoritesStream(String userId) {
    try {
      return _firestore
          .collection(_favoritesCollection)
          .doc(userId)
          .snapshots()
          .asyncMap((favoritesSnapshot) async {
        if (!favoritesSnapshot.exists) {
          return <Property>[];
        }

        final favoriteIds =
            List<String>.from(favoritesSnapshot.data()?['propertyIds'] ?? []);

        if (favoriteIds.isEmpty) {
          return <Property>[];
        }

        // Get properties in batches
        final List<Property> favorites = [];
        const int batchSize = 10;

        for (int i = 0; i < favoriteIds.length; i += batchSize) {
          final batch = favoriteIds.skip(i).take(batchSize).toList();

          final querySnapshot = await _firestore
              .collection(_propertiesCollection)
              .where(FieldPath.documentId, whereIn: batch)
              .get();

          favorites.addAll(
            querySnapshot.docs
                .map((doc) => Property.fromMap(doc.id, doc.data()))
                .toList(),
          );
        }

        return favorites;
      });
    } catch (e) {
      throw Exception('Failed to get user favorites stream: $e');
    }
  }
}
