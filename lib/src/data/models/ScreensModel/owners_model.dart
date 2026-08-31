import 'package:cloud_firestore/cloud_firestore.dart';

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
  });

  // Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'name': name,
      'phoneNumber': phoneNumber,
      'countryCode': countryCode,
      'typeOfProperties': typeOfProperties,
      'propertyLocation': propertyLocation,
      'notes': notes,
      'pickUpLocation': pickUpLocation,
      'pickUpLatitude': pickUpLatitude,
      'pickUpLongitude': pickUpLongitude,
      'pickUpAddress': pickUpAddress,
      'uploadedFileName': uploadedFileName,
      'mediaUrl': mediaUrl,
      'mediaUrls': mediaUrls,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  // Create from Firestore document
  factory OwnerModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Safe timestamp handling - server timestamps can be null during read operations
    DateTime parseTimestamp(dynamic timestamp) {
      if (timestamp == null) {
        return DateTime.now();
      }
      if (timestamp is Timestamp) {
        return timestamp.toDate();
      }
      if (timestamp is DateTime) {
        return timestamp;
      }
      // Fallback for other types or malformed data
      return DateTime.now();
    }

    return OwnerModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      name: data['name'] ?? '',
      phoneNumber: data['phoneNumber'] ?? '',
      countryCode: data['countryCode'] ?? '+971',
      typeOfProperties: data['typeOfProperties'] ?? '',
      propertyLocation: data['propertyLocation'] ?? '',
      notes: data['notes'] ?? '',
      pickUpLocation: data['pickUpLocation'] ?? '',
      pickUpLatitude: data['pickUpLatitude'] ?? 0.0,
      pickUpLongitude: data['pickUpLongitude'] ?? 0.0,
      pickUpAddress: data['pickUpAddress'] ?? '',
      uploadedFileName: data['uploadedFileName'],
      mediaUrl: data['mediaUrl'],
      mediaUrls: List<String>.from(data['mediaUrls'] ?? []),
      createdAt: parseTimestamp(data['createdAt']),
      updatedAt: parseTimestamp(data['updatedAt']),
    );
  }

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
    );
  }
}
