
class WatchmenModel {
  final String? id;
  final String? userId;
  final String name;
  final String countryCode;
  final String phoneNumber;
  final String buildingName;
  final String notes;
  final String buildingLocation;
  final String pickUpLocation;
  final double? pickUpLatitude;
  final double? pickUpLongitude;
  final String pickUpAddress;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  WatchmenModel({
    this.id,
    this.userId,
    required this.name,
    required this.countryCode,
    required this.phoneNumber,
    required this.buildingName,
    required this.notes,
    required this.buildingLocation,
    required this.pickUpLocation,
    this.pickUpLatitude,
    this.pickUpLongitude,
    required this.pickUpAddress,
    this.createdAt,
    this.updatedAt,
  });

  // Copy with method for updates
  WatchmenModel copyWith({
    String? id,
    String? userId,
    String? name,
    String? countryCode,
    String? phoneNumber,
    String? buildingName,
    String? notes,
    String? buildingLocation,
    String? pickUpLocation,
    double? pickUpLatitude,
    double? pickUpLongitude,
    String? pickUpAddress,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return WatchmenModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      countryCode: countryCode ?? this.countryCode,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      buildingName: buildingName ?? this.buildingName,
      notes: notes ?? this.notes,
      buildingLocation: buildingLocation ?? this.buildingLocation,
      pickUpLocation: pickUpLocation ?? this.pickUpLocation,
      pickUpLatitude: pickUpLatitude ?? this.pickUpLatitude,
      pickUpLongitude: pickUpLongitude ?? this.pickUpLongitude,
      pickUpAddress: pickUpAddress ?? this.pickUpAddress,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
