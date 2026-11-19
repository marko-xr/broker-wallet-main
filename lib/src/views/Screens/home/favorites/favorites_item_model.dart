import 'package:broker_wallet/src/data/models/ScreensModel/brokers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offices_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/watchmen_model.dart';
import 'package:broker_wallet/src/services/favorites_local_cache.dart';
import 'package:hive/hive.dart';

import 'favorite_card_media.dart';

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
      // The card's private photo or video frame, by identity (no link).
      media: FavoriteCardMedia.fromStored(entityData),
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

  /// The private photo (or a video's still frame) the card shows, for records
  /// whose media is private. Takes the place of [imageUrl], which only
  /// carries a plain URL.
  final FavoriteCardMedia? media;
  final DateTime addedAt;
  final dynamic originalData; // Store the original model data
  final FavoriteRequestSummary? savedRequestSummary;
  final Map<String, String>? savedCardFields;

  FavoriteItem({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    this.imageUrl,
    this.media,
    required this.addedAt,
    this.originalData,
    this.savedRequestSummary,
    this.savedCardFields,
  });

  /// What an Offer, Owner, Office, Broker or Watchman card shows: from the
  /// record when the server has answered, otherwise the saved copy's fields
  /// (null for an older saved card that has none: it shows no fields, never
  /// "not available" for data that simply has not loaded yet).
  Map<String, String>? get cardFields {
    final data = originalData;
    if (data is OfferModel) {
      return {
        'propertyType': data.propertyType ?? '',
        'specificPropertyType': data.specificPropertyType,
        'selectedCity': data.selectedCity,
        'squareFootage': data.squareFootage,
      };
    }
    if (data is OwnerModel) {
      return {
        'name': data.name,
        'typeOfProperties': data.typeOfProperties,
        'propertyLocation': data.propertyLocation,
        'phoneNumber': data.phoneNumber,
      };
    }
    if (data is OfficeModel) {
      return {
        'officeName': data.officeName,
        'officeLocation': data.officeLocation,
        'phoneNumber': data.phoneNumber,
      };
    }
    if (data is BrokerModel) {
      return {
        'name': data.name,
        'phoneNumber': data.phoneNumber,
        'notes': data.notes,
      };
    }
    if (data is WatchmenModel) {
      return {
        'name': data.name,
        'buildingName': data.buildingName,
        'phoneNumber': data.phoneNumber,
      };
    }
    return isRequest ? null : savedCardFields;
  }

  FavoriteRequestSummary? get requestSummary {
    if (!isRequest) return null;
    final request = originalData;
    if (request is! RequestModel) return savedRequestSummary;
    return (
      requestType: request.requestType,
      propertyType: request.propertyType,
      specificPropertyType: request.specificPropertyType,
      squareFootage: request.squareFootage,
      selectedCity: request.selectedCity,
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
