import 'package:cloud_firestore/cloud_firestore.dart';

class BrokerModel {
  final String? id;
  final String? userId;
  final String name;
  final String countryCode;
  final String phoneNumber;
  final String notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  BrokerModel({
    this.id,
    this.userId,
    required this.name,
    required this.countryCode,
    required this.phoneNumber,
    required this.notes,
    this.createdAt,
    this.updatedAt,
  });

  // Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'name': name,
      'countryCode': countryCode,
      'phoneNumber': phoneNumber,
      'notes': notes,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  // Create from Firestore document
  factory BrokerModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return BrokerModel(
      id: doc.id,
      userId: data['userId'],
      name: data['name'] ?? '',
      countryCode: data['countryCode'] ?? '+971',
      phoneNumber: data['phoneNumber'] ?? '',
      notes: data['notes'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  // Copy with method for updates
  BrokerModel copyWith({
    String? id,
    String? userId,
    String? name,
    String? countryCode,
    String? phoneNumber,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BrokerModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      countryCode: countryCode ?? this.countryCode,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
