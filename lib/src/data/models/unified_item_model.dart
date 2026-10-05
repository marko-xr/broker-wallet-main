// lib/src/data/models/unified_item_model.dart

enum ItemType { request, offer, broker, owner, office, watchmen, quotation }

class UnifiedItemModel {
  final String id;
  final String title;
  final String subtitle;
  final ItemType type;

  /// When the record was created. Only the record's own time while
  /// [hasCreatedAt] is true; otherwise a stand-in so something can be drawn.
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Whether [createdAt] is the record's own creation time. It is false when the
  /// record carried none and [createdAt] is only today's date for display; that
  /// says nothing about the record's age, so a filter by age never counts the
  /// record as recent.
  final bool hasCreatedAt;
  final String? price; // For offers and requests
  final double? minPrice; // For filtering by price
  final double? maxPrice; // For filtering by price
  final dynamic originalModel; // Store the complete original model object

  UnifiedItemModel({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.type,
    required this.createdAt,
    required this.updatedAt,
    this.hasCreatedAt = true,
    this.price,
    this.minPrice,
    this.maxPrice,
    required this.originalModel,
  });

  // Factory methods to create from different models
  factory UnifiedItemModel.fromRequest(dynamic request) {
    final minPrice = _parsePrice(request.minPrice);
    final maxPrice = _parsePrice(request.maxPrice);

    return UnifiedItemModel(
      id: request.id ?? '',
      title: '${request.requestType.toUpperCase()} - ${request.selectedCity}',
      subtitle:
          '${request.propertyType ?? 'Property'} • ${request.specificPropertyType}',
      type: ItemType.request,
      createdAt: request.createdAt,
      updatedAt: request.updatedAt,
      price: _formatPriceRange(request.minPrice, request.maxPrice),
      minPrice: minPrice,
      maxPrice: maxPrice,
      originalModel: request,
    );
  }

  factory UnifiedItemModel.fromOffer(dynamic offer) {
    final minPrice = _parsePrice(offer.minPrice);
    final maxPrice = _parsePrice(offer.maxPrice);

    return UnifiedItemModel(
      id: offer.id ?? '',
      title: '${offer.offerType.toUpperCase()} - ${offer.selectedCity}',
      subtitle:
          '${offer.propertyType ?? 'Property'} • ${offer.specificPropertyType}',
      type: ItemType.offer,
      createdAt: offer.createdAt,
      updatedAt: offer.updatedAt,
      price: _formatPriceRange(offer.minPrice, offer.maxPrice),
      minPrice: minPrice,
      maxPrice: maxPrice,
      originalModel: offer,
    );
  }

  factory UnifiedItemModel.fromBroker(dynamic broker) {
    return UnifiedItemModel(
      id: broker.id ?? '',
      title: broker.name,
      subtitle: broker.phoneNumber,
      type: ItemType.broker,
      createdAt: broker.createdAt ?? DateTime.now(),
      updatedAt: broker.updatedAt ?? DateTime.now(),
      hasCreatedAt: broker.createdAt != null,
      originalModel: broker,
    );
  }

  factory UnifiedItemModel.fromOwner(dynamic owner) {
    return UnifiedItemModel(
      id: owner.id ?? '',
      title: owner.name,
      subtitle: '${owner.typeOfProperties} • ${owner.propertyLocation}',
      type: ItemType.owner,
      createdAt: owner.createdAt,
      updatedAt: owner.updatedAt,
      originalModel: owner,
    );
  }

  factory UnifiedItemModel.fromOffice(dynamic office) {
    return UnifiedItemModel(
      id: office.id ?? '',
      title: office.officeName,
      subtitle: '${office.managerName} • ${office.officeLocation}',
      type: ItemType.office,
      createdAt: office.createdAt ?? DateTime.now(),
      updatedAt: office.updatedAt ?? DateTime.now(),
      hasCreatedAt: office.createdAt != null,
      originalModel: office,
    );
  }

  factory UnifiedItemModel.fromWatchmen(dynamic watchmen) {
    return UnifiedItemModel(
      id: watchmen.id ?? '',
      title: watchmen.name,
      subtitle: '${watchmen.buildingName} • ${watchmen.buildingLocation}',
      type: ItemType.watchmen,
      createdAt: watchmen.createdAt ?? DateTime.now(),
      updatedAt: watchmen.updatedAt ?? DateTime.now(),
      hasCreatedAt: watchmen.createdAt != null,
      originalModel: watchmen,
    );
  }

  /// A price as the forms store it: digits, possibly with thousands separators
  /// (the same normalization the Supabase payload builder applies on write).
  /// Text that is not a finite, non-negative number is no price at all, so a
  /// record carrying it is never ranked by it.
  static double? _parsePrice(String? text) {
    final normalized = text?.replaceAll(',', '').trim() ?? '';
    if (normalized.isEmpty) return null;
    final value = double.tryParse(normalized);
    if (value == null || !value.isFinite || value < 0) return null;
    return value;
  }

  // Helper method to format price range
  static String? _formatPriceRange(String minPrice, String maxPrice) {
    if (minPrice.isNotEmpty && maxPrice.isNotEmpty) {
      return '$minPrice - $maxPrice AED';
    } else if (minPrice.isNotEmpty) {
      return 'From $minPrice AED';
    } else if (maxPrice.isNotEmpty) {
      return 'Up to $maxPrice AED';
    }
    return null;
  }

  // Get the average price for sorting
  double? get averagePrice {
    if (minPrice != null && maxPrice != null) {
      return (minPrice! + maxPrice!) / 2;
    } else if (minPrice != null) {
      return minPrice;
    } else if (maxPrice != null) {
      return maxPrice;
    }
    return null;
  }

  // What "recently added" and "this week" mean lives in one place,
  // HomeFilterRules, so a record cannot be recent by one definition and not by
  // another.
}
