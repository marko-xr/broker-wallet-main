// lib/src/data/models/unified_item_model.dart

enum ItemType { request, offer, broker, owner, office, watchmen, quotation }

class UnifiedItemModel {
  final String id;
  final String title;
  final String subtitle;
  final ItemType type;
  final DateTime createdAt;
  final DateTime updatedAt;
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
    this.price,
    this.minPrice,
    this.maxPrice,
    required this.originalModel,
  });

  // Factory methods to create from different models
  factory UnifiedItemModel.fromRequest(dynamic request) {
    final minPrice =
        request.minPrice.isNotEmpty ? double.tryParse(request.minPrice) : null;
    final maxPrice =
        request.maxPrice.isNotEmpty ? double.tryParse(request.maxPrice) : null;

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
    final minPrice =
        offer.minPrice.isNotEmpty ? double.tryParse(offer.minPrice) : null;
    final maxPrice =
        offer.maxPrice.isNotEmpty ? double.tryParse(offer.maxPrice) : null;

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
      originalModel: watchmen,
    );
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

  // Check if item was created in the last 12 hours
  bool get isRecentlyAdded {
    final now = DateTime.now();
    final difference = now.difference(createdAt);
    return difference.inHours <= 12;
  }

  // Check if item was created in the last week
  bool get isThisWeek {
    final now = DateTime.now();
    final difference = now.difference(createdAt);
    return difference.inDays <= 7;
  }
}
