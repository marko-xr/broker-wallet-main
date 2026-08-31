import 'package:hive/hive.dart';

// Hive model for cached favorites - denormalized for instant display
part 'favorites_item_model.g.dart';

@HiveType(typeId: 1)
class CachedFavoriteItem {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String type;

  @HiveField(2)
  final String title;

  @HiveField(3)
  final String subtitle;

  @HiveField(4)
  final String? imageUrl;

  @HiveField(5)
  final String? thumbnailUrl; // Smaller image for grid

  @HiveField(6)
  final DateTime addedAt;

  @HiveField(7)
  final DateTime cachedAt;

  @HiveField(8)
  final String? entityData; // JSON string of minimal entity data

  CachedFavoriteItem({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    this.imageUrl,
    this.thumbnailUrl,
    required this.addedAt,
    required this.cachedAt,
    this.entityData,
  });

  // Convert to display model
  FavoriteItem toFavoriteItem() {
    return FavoriteItem(
      id: id,
      type: type,
      title: title,
      subtitle: subtitle,
      imageUrl: imageUrl,
      addedAt: addedAt,
      originalData: null, // Will be loaded when needed
    );
  }

  // Helper methods to determine type
  bool get isOffer => type == 'offers';
  bool get isRequest => type == 'requests';
  bool get isOwner => type == 'owners';
  bool get isOffice => type == 'offices';
  bool get isBroker => type == 'brokers';
  bool get isWatchmen => type == 'watchmen';

  // Get appropriate icon for each type
  String get typeIcon {
    switch (type) {
      case 'requests':
        return 'assets/icons/requested-svg.svg';
      case 'offers':
        return 'assets/icons/offers-svg.svg';
      case 'owners':
        return 'assets/icons/owners-svg.svg';
      case 'offices':
        return 'assets/icons/offices-svg.svg';
      case 'brokers':
        return 'assets/icons/brokers-svg.svg';
      case 'watchmen':
        return 'assets/icons/watchman-svg.svg';
      default:
        return 'assets/icons/offices-svg.svg';
    }
  }

  // Get type display name
  String get typeDisplayName {
    switch (type) {
      case 'offers':
        return 'Offer';
      case 'requests':
        return 'Request';
      case 'owners':
        return 'Owner';
      case 'offices':
        return 'Office';
      case 'brokers':
        return 'Broker';
      case 'watchmen':
        return 'Watchmen';
      default:
        return 'Item';
    }
  }
}

// Display model (non-Hive)
class FavoriteItem {
  final String id;
  final String type;
  final String title;
  final String subtitle;
  final String? imageUrl;
  final DateTime addedAt;
  final dynamic originalData; // Store the original model data

  FavoriteItem({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    this.imageUrl,
    required this.addedAt,
    this.originalData,
  });

  // Helper methods to determine type
  bool get isOffer => type == 'offers';
  bool get isRequest => type == 'requests';
  bool get isOwner => type == 'owners';
  bool get isOffice => type == 'offices';
  bool get isBroker => type == 'brokers';
  bool get isWatchmen => type == 'watchmen';

  // Get appropriate icon for each type
  String get typeIcon {
    switch (type) {
      case 'requests':
        return 'assets/icons/requested-svg.svg';
      case 'offers':
        return 'assets/icons/offers-svg.svg';
      case 'owners':
        return 'assets/icons/owners-svg.svg';
      case 'offices':
        return 'assets/icons/offices-svg.svg';
      case 'brokers':
        return 'assets/icons/brokers-svg.svg';
      case 'watchmen':
        return 'assets/icons/watchman-svg.svg';
      default:
        return 'assets/icons/offices-svg.svg';
    }
  }

  // Get type display name
  String get typeDisplayName {
    switch (type) {
      case 'offers':
        return 'Offer';
      case 'requests':
        return 'Request';
      case 'owners':
        return 'Owner';
      case 'offices':
        return 'Office';
      case 'brokers':
        return 'Broker';
      case 'watchmen':
        return 'Watchmen';
      default:
        return 'Item';
    }
  }
}
