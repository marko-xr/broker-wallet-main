
class OwnerModel {
  final String? id;
  final String userId;
  final String name;
  final String phoneNumber;
  final String countryCode;
  final String typeOfProperties;
  final String propertyLocation;
  final String notes;
  final String pickUpLocation;
  final double? pickUpLatitude;
  final double? pickUpLongitude;
  final String pickUpAddress;
  final String? uploadedFileName;
  final String? mediaUrl; // Primary media URL
  final List<String> mediaUrls; // Multiple media URLs
  final DateTime createdAt;
  final DateTime updatedAt;

  /// The ids of the Owner record's `ready` media in gallery order, as the
  /// Owner read itself returned them (tracker §7AZ, M2-1): identity only —
  /// no link. Empty when the read carried none. Nothing displays from it yet.
  final List<String> listedMediaObjectIds;

  OwnerModel({
    this.id,
    required this.userId,
    required this.name,
    required this.phoneNumber,
    required this.countryCode,
    required this.typeOfProperties,
    required this.propertyLocation,
    required this.notes,
    required this.pickUpLocation,
    required this.pickUpLatitude,
    required this.pickUpLongitude,
    required this.pickUpAddress,
    this.uploadedFileName,
    this.mediaUrl,
    required this.mediaUrls,
    required this.createdAt,
    required this.updatedAt,
    this.listedMediaObjectIds = const <String>[],
  });

  // Copy with method for updates
  OwnerModel copyWith({
    String? id,
    String? userId,
    String? name,
    String? phoneNumber,
    String? countryCode,
    String? typeOfProperties,
    String? propertyLocation,
    String? notes,
    String? propertiesLocation,
    String? uploadedFileName,
    String? mediaUrl,
    List<String>? mediaUrls,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? listedMediaObjectIds,
  }) {
    return OwnerModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      countryCode: countryCode ?? this.countryCode,
      typeOfProperties: typeOfProperties ?? this.typeOfProperties,
      propertyLocation: propertyLocation ?? this.propertyLocation,
      notes: notes ?? this.notes,
      pickUpLocation: pickUpLocation,
      pickUpLatitude: pickUpLatitude ?? this.pickUpLatitude,
      pickUpLongitude: pickUpLongitude ?? this.pickUpLongitude,
      pickUpAddress: pickUpAddress,
      uploadedFileName: uploadedFileName ?? this.uploadedFileName,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      mediaUrls: mediaUrls ?? this.mediaUrls,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      listedMediaObjectIds: listedMediaObjectIds ?? this.listedMediaObjectIds,
    );
  }
}
