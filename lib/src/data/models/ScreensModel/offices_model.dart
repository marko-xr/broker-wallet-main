import 'package:cloud_firestore/cloud_firestore.dart';

class OfficeModel {
  final String? id;
  final String? userId;
  final String officeName;
  final String managerName;
  final String countryCode;
  final String phoneNumber;
  final String officeLocation;
  final String notes;
  final String pickUpLocation;
  final double? pickUpLatitude;
  final double? pickUpLongitude;
  final String pickUpAddress;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  OfficeModel({
    this.id,
    this.userId,
    required this.officeName,
    required this.managerName,
    required this.countryCode,
    required this.phoneNumber,
    required this.officeLocation,
    required this.notes,
    required this.pickUpLocation,
    this.pickUpLatitude,
    this.pickUpLongitude,
    required this.pickUpAddress,
    this.createdAt,
    this.updatedAt,
  });

  // Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'officeName': officeName,
      'managerName': managerName,
      'countryCode': countryCode,
      'phoneNumber': phoneNumber,
      'officeLocation': officeLocation,
      'notes': notes,
      'pickUpLocation': pickUpLocation,
      'pickUpLatitude': pickUpLatitude,
      'pickUpLongitude': pickUpLongitude,
      'pickUpAddress': pickUpAddress,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  // Create from Firestore document
  factory OfficeModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return OfficeModel(
      id: doc.id,
      userId: data['userId'],
      officeName: data['officeName'] ?? '',
      managerName: data['managerName'] ?? '',
      countryCode: data['countryCode'] ?? '+971',
      phoneNumber: data['phoneNumber'] ?? '',
      officeLocation: data['officeLocation'] ?? '',
      notes: data['notes'] ?? '',
      pickUpLocation: data['pickUpLocation'] ?? '',
      pickUpLatitude: (data['pickUpLatitude'] as num?)?.toDouble(),
      pickUpLongitude: (data['pickUpLongitude'] as num?)?.toDouble(),
      pickUpAddress: data['pickUpAddress'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  // Copy with method for updates
  OfficeModel copyWith({
    String? id,
    String? userId,
    String? officeName,
    String? managerName,
    String? countryCode,
    String? phoneNumber,
    String? officeLocation,
    String? notes,
    String? pickUpLocation,
    double? pickUpLatitude,
    double? pickUpLongitude,
    String? pickUpAddress,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return OfficeModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      officeName: officeName ?? this.officeName,
      managerName: managerName ?? this.managerName,
      countryCode: countryCode ?? this.countryCode,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      officeLocation: officeLocation ?? this.officeLocation,
      notes: notes ?? this.notes,
      pickUpLocation: pickUpLocation ?? this.pickUpLocation,
      pickUpLatitude: pickUpLatitude ?? this.pickUpLatitude,
      pickUpLongitude: pickUpLongitude ?? this.pickUpLongitude,
      pickUpAddress: pickUpAddress ?? this.pickUpAddress,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
