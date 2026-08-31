import 'package:cloud_firestore/cloud_firestore.dart';
import '../property_status.dart';

class RequestModel {
  final String? id;
  final String userId;
  final String requestType; // 'rent' or 'sell'
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
  final PropertyStatus status; // Property availability status
  final DateTime createdAt;
  final DateTime updatedAt;

  RequestModel({
    this.id,
    required this.userId,
    required this.requestType,
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
    this.status = PropertyStatus.active, // Default to active for requests
    required this.createdAt,
    required this.updatedAt,
  });

  // Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'requestType': requestType,
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
      'status': status.toFirestoreString(),
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  // Create from Firestore document
  factory RequestModel.fromFirestore(DocumentSnapshot doc) {
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

    return RequestModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      requestType: data['requestType'] ?? 'rent',
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
      status: _normalizeStatus(data['status']),
      createdAt: parseTimestamp(data['createdAt']),
      updatedAt: parseTimestamp(data['updatedAt']),
    );
  }

  /// Create a request model from the Supabase/PostgREST row shape.
  ///
  /// The current UI model is intentionally kept unchanged while the backend is
  /// migrated. This adapter translates snake_case PostgreSQL columns and the
  /// request_areas child table into the legacy model fields expected by the UI.
  factory RequestModel.fromSupabaseMap(Map<String, dynamic> data) {
    DateTime parseDate(dynamic value) {
      if (value is DateTime) {
        return value.toLocal();
      }

      final parsed = DateTime.tryParse(value?.toString() ?? '');
      return parsed?.toLocal() ?? DateTime.now();
    }

    int parseInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    String numberText(dynamic value) {
      if (value == null) return '';
      if (value is num && value % 1 == 0) {
        return value.toInt().toString();
      }
      return value.toString();
    }

    final areaRows = <Map<String, dynamic>>[];
    final rawAreas = data['request_areas'];
    if (rawAreas is List) {
      for (final item in rawAreas) {
        if (item is Map) {
          areaRows.add(Map<String, dynamic>.from(item));
        }
      }
    }

    areaRows.sort(
      (a, b) => parseInt(a['ordinal']).compareTo(parseInt(b['ordinal'])),
    );

    final selectedAreas = areaRows
        .map((row) => row['area']?.toString() ?? '')
        .where((area) => area.isNotEmpty)
        .toList(growable: false);

    return RequestModel(
      id: data['id']?.toString(),
      userId: data['owner_id']?.toString() ?? '',
      requestType: data['request_type']?.toString() ?? 'rent',
      selectedCity: data['selected_city']?.toString() ?? '',
      selectedAreas: selectedAreas,
      location: data['location_text']?.toString() ?? '',
      phoneNumber: data['phone_number']?.toString() ?? '',
      countryCode: data['country_code']?.toString() ?? '+971',
      minPrice: numberText(data['min_price']),
      maxPrice: numberText(data['max_price']),
      squareFootage: numberText(data['square_footage']),
      notes: data['notes']?.toString() ?? '',
      propertyType: data['property_type']?.toString(),
      specificPropertyType: data['specific_property_type']?.toString() ?? '',
      rooms: parseInt(data['rooms']),
      bathrooms: parseInt(data['bathrooms']),
      status: _normalizeStatus(data['status']),
      createdAt: parseDate(data['created_at']),
      updatedAt: parseDate(data['updated_at']),
    );
  }

  // Copy with method for updates
  RequestModel copyWith({
    String? id,
    String? userId,
    String? requestType,
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
    PropertyStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return RequestModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      requestType: requestType ?? this.requestType,
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
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static PropertyStatus _normalizeStatus(dynamic statusValue) {
    final parsedStatus =
        PropertyStatus.fromString((statusValue ?? 'active').toString());

    // Legacy requests may store `available`; treat them as `active` going forward
    if (parsedStatus == PropertyStatus.available) {
      return PropertyStatus.active;
    }

    return parsedStatus;
  }
}
