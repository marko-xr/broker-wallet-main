import 'package:broker_wallet/src/data/models/property.dart';

/// Abstract repository interface for property operations
/// This allows switching between different data sources for properties
abstract class PropertyRepository {
  /// Get all properties
  Future<List<Property>> getAllProperties();

  /// Get properties by category
  Future<List<Property>> getPropertiesByCategory(PropertyCategory category);

  /// Get property by ID
  Future<Property?> getPropertyById(String id);

  /// Create new property
  Future<String> createProperty(Property property);

  /// Update property
  Future<void> updateProperty(Property property);

  /// Delete property
  Future<void> deleteProperty(String id);

  /// Search properties
  Future<List<Property>> searchProperties({
    String? query,
    PropertyCategory? category,
    double? minPrice,
    double? maxPrice,
    String? location,
  });

  /// Get user's properties
  Future<List<Property>> getUserProperties(String userId);

  /// Get user's favorite properties
  Future<List<Property>> getUserFavorites(String userId);

  /// Add property to favorites
  Future<void> addToFavorites(String userId, String propertyId);

  /// Remove property from favorites
  Future<void> removeFromFavorites(String userId, String propertyId);

  /// Stream of properties
  Stream<List<Property>> get propertiesStream;

  /// Stream of user's favorite properties
  Stream<List<Property>> getUserFavoritesStream(String userId);
}
