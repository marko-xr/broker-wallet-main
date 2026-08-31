import 'package:cloud_firestore/cloud_firestore.dart';
import '../property_status.dart';

class OfferModel {
  final String? id;
  final String userId;
  final String offerType; // 'rent' or 'sell'
  final String selectedCity;
  final List<String> selectedAreas;
  final String location;
  final String phoneNumber;
  final String countryCode;
  final String minPrice;
  final String maxPrice;
  final String squareFootage;
  final String notes;
  final String? propertyType;
  final String specificPropertyType;
  final int rooms;
  final int bathrooms;
  final String pickUpLocation;
  final double? pickUpLatitude;
  final double? pickUpLongitude;
  final String pickUpAddress;
  final String uploadedFileName;
  final String? mediaUrl;
  final PropertyStatus status; // Property availability status
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> mediaUrls;

  OfferModel({
    this.id,
    required this.userId,
    required this.offerType,
    required this.selectedCity,
    required this.selectedAreas,
    required this.location,
    required this.phoneNumber,
    required this.countryCode,
    required this.minPrice,
    required this.maxPrice,
    this.squareFootage = '',
    required this.notes,
    this.propertyType,
    required this.specificPropertyType,
    required this.rooms,
    required this.bathrooms,
    required this.pickUpLocation,
    required this.pickUpLatitude,
    required this.pickUpLongitude,
    required this.pickUpAddress,
    required this.uploadedFileName,
    this.mediaUrl,
    this.status = PropertyStatus.available, // Default to available
    required this.createdAt,
    required this.updatedAt,
    required this.mediaUrls,
  });

  // Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'offerType': offerType,
      'selectedCity': selectedCity,
      'selectedAreas': selectedAreas,
      'location': location,
      'phoneNumber': phoneNumber,
      'countryCode': countryCode,
      'minPrice': minPrice,
      'maxPrice': maxPrice,
      'squareFootage': squareFootage,
      'notes': notes,
      'propertyType': propertyType,
      'specificPropertyType': specificPropertyType,
      'rooms': rooms,
      'bathrooms': bathrooms,
      'pickUpLocation': pickUpLocation,
      'pickUpLatitude': pickUpLatitude,
      'pickUpLongitude': pickUpLongitude,
      'pickUpAddress': pickUpAddress,
      'uploadedFileName': uploadedFileName,
      'mediaUrl': mediaUrl,
      'status': status.toFirestoreString(),
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'mediaUrls': mediaUrls,
    };
  }

  // Create from Firestore document
  factory OfferModel.fromFirestore(DocumentSnapshot doc) {
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

    return OfferModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      offerType: data['offerType'] ?? 'rent',
      selectedCity: data['selectedCity'] ?? '',
      selectedAreas: List<String>.from(data['selectedAreas'] ?? []),
      location: data['location'] ?? '',
      phoneNumber: data['phoneNumber'] ?? '',
      countryCode: data['countryCode'] ?? '+971',
      minPrice: data['minPrice'] ?? '',
      maxPrice: data['maxPrice'] ?? '',
      squareFootage: data['squareFootage'] ?? '',
      notes: data['notes'] ?? '',
      propertyType: data['propertyType'],
      specificPropertyType: data['specificPropertyType'] ?? '',
      rooms: data['rooms'] ?? 1,
      bathrooms: data['bathrooms'] ?? 1,
      pickUpLocation: data['pickUpLocation'] ?? '',
      pickUpLatitude: data['pickUpLatitude'] ?? 0.0,
      pickUpLongitude: data['pickUpLongitude'] ?? 0.0,
      pickUpAddress: data['pickUpAddress'] ?? '',
      uploadedFileName: data['uploadedFileName'] ?? '',
      mediaUrl: data['mediaUrl'],
      status: PropertyStatus.fromString(data['status'] ?? 'available'),
      createdAt: parseTimestamp(data['createdAt']),
      updatedAt: parseTimestamp(data['updatedAt']),
      mediaUrls: List<String>.from(data['mediaUrls'] ?? []),
    );
  }

  // Copy with method for updates
  OfferModel copyWith({
    String? id,
    String? userId,
    String? offerType,
    String? selectedCity,
    List<String>? selectedAreas,
    String? location,
    String? phoneNumber,
    String? countryCode,
    String? minPrice,
    String? maxPrice,
    String? squareFootage,
    String? notes,
    String? propertyType,
    String? specificPropertyType,
    int? rooms,
    int? bathrooms,
    String? pickUpLocation,
    double? pickUpLatitude,
    double? pickUpLongitude,
    String? pickUpAddress,
    String? uploadedFileName,
    String? mediaUrl,
    PropertyStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? mediaUrls,
  }) {
    return OfferModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      offerType: offerType ?? this.offerType,
      selectedCity: selectedCity ?? this.selectedCity,
      selectedAreas: selectedAreas ?? this.selectedAreas,
      location: location ?? this.location,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      countryCode: countryCode ?? this.countryCode,
      minPrice: minPrice ?? this.minPrice,
      maxPrice: maxPrice ?? this.maxPrice,
      squareFootage: squareFootage ?? this.squareFootage,
      notes: notes ?? this.notes,
      propertyType: propertyType ?? this.propertyType,
      specificPropertyType: specificPropertyType ?? this.specificPropertyType,
      rooms: rooms ?? this.rooms,
      bathrooms: bathrooms ?? this.bathrooms,
      pickUpLocation: pickUpLocation ?? this.pickUpLocation,
      pickUpLatitude: pickUpLatitude ?? this.pickUpLatitude,
      pickUpLongitude: pickUpLongitude ?? this.pickUpLongitude,
      pickUpAddress: pickUpAddress ?? this.pickUpAddress,
      uploadedFileName: uploadedFileName ?? this.uploadedFileName,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      mediaUrls: mediaUrls ?? this.mediaUrls,
    );
  }
}
