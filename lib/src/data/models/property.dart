import 'package:google_maps_flutter/google_maps_flutter.dart';

enum PropertyCategory { requested, offer, watchman, office }

class Property {
  final String id;
  final PropertyCategory category;
  final LatLng location;
  final double price;
  final String imageUrl;

  Property({
    required this.id,
    required this.category,
    required this.location,
    required this.price,
    required this.imageUrl,
  });

  /// Create Property from Firestore document
  factory Property.fromMap(String id, Map<String, dynamic> map) {
    return Property(
      id: id,
      category: PropertyCategory.values.firstWhere(
        (category) => category.toString().split('.').last == map['category'],
        orElse: () => PropertyCategory.requested,
      ),
      location: LatLng(
        map['location']['latitude']?.toDouble() ?? 0.0,
        map['location']['longitude']?.toDouble() ?? 0.0,
      ),
      price: map['price']?.toDouble() ?? 0.0,
      imageUrl: map['imageUrl'] ?? '',
    );
  }

  /// Convert Property to map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'category': category.toString().split('.').last,
      'location': {
        'latitude': location.latitude,
        'longitude': location.longitude,
      },
      'price': price,
      'imageUrl': imageUrl,
    };
  }

  // 5 examples per category around central Dubai
  static final List<Property> sampleProperties = [
    // Requested (red)
    Property(
      id: 'req1',
      category: PropertyCategory.requested,
      location: LatLng(25.205, 55.270),
      price: 150000,
      imageUrl: 'https://via.placeholder.com/150',
    ),
    Property(
      id: 'req2',
      category: PropertyCategory.requested,
      location: LatLng(25.207, 55.271),
      price: 170000,
      imageUrl: 'https://via.placeholder.com/150',
    ),
    Property(
      id: 'req3',
      category: PropertyCategory.requested,
      location: LatLng(25.203, 55.269),
      price: 120000,
      imageUrl: 'https://via.placeholder.com/150',
    ),
    Property(
      id: 'req4',
      category: PropertyCategory.requested,
      location: LatLng(25.204, 55.273),
      price: 200000,
      imageUrl: 'https://via.placeholder.com/150',
    ),
    Property(
      id: 'req5',
      category: PropertyCategory.requested,
      location: LatLng(25.206, 55.268),
      price: 130000,
      imageUrl: 'https://via.placeholder.com/150',
    ),

    // Offers (green)
    Property(
      id: 'off1',
      category: PropertyCategory.offer,
      location: LatLng(25.202, 55.275),
      price: 250000,
      imageUrl: 'https://via.placeholder.com/150',
    ),
    Property(
      id: 'off2',
      category: PropertyCategory.offer,
      location: LatLng(25.208, 55.276),
      price: 230000,
      imageUrl: 'https://via.placeholder.com/150',
    ),
    Property(
      id: 'off3',
      category: PropertyCategory.offer,
      location: LatLng(25.209, 55.272),
      price: 210000,
      imageUrl: 'https://via.placeholder.com/150',
    ),
    Property(
      id: 'off4',
      category: PropertyCategory.offer,
      location: LatLng(25.201, 55.271),
      price: 190000,
      imageUrl: 'https://via.placeholder.com/150',
    ),
    Property(
      id: 'off5',
      category: PropertyCategory.offer,
      location: LatLng(25.200, 55.269),
      price: 220000,
      imageUrl: 'https://via.placeholder.com/150',
    ),

    // Watchmen (blue)
    Property(
      id: 'wat1',
      category: PropertyCategory.watchman,
      location: LatLng(25.210, 55.267),
      price: 180000,
      imageUrl: 'https://via.placeholder.com/150',
    ),
    Property(
      id: 'wat2',
      category: PropertyCategory.watchman,
      location: LatLng(25.211, 55.268),
      price: 160000,
      imageUrl: 'https://via.placeholder.com/150',
    ),
    Property(
      id: 'wat3',
      category: PropertyCategory.watchman,
      location: LatLng(25.212, 55.266),
      price: 140000,
      imageUrl: 'https://via.placeholder.com/150',
    ),
    Property(
      id: 'wat4',
      category: PropertyCategory.watchman,
      location: LatLng(25.213, 55.269),
      price: 170000,
      imageUrl: 'https://via.placeholder.com/150',
    ),
    Property(
      id: 'wat5',
      category: PropertyCategory.watchman,
      location: LatLng(25.214, 55.265),
      price: 155000,
      imageUrl: 'https://via.placeholder.com/150',
    ),

    // Offices (orange)
    Property(
      id: 'offc1',
      category: PropertyCategory.office,
      location: LatLng(25.207, 55.265),
      price: 300000,
      imageUrl: 'https://via.placeholder.com/150',
    ),
    Property(
      id: 'offc2',
      category: PropertyCategory.office,
      location: LatLng(25.205, 55.266),
      price: 320000,
      imageUrl: 'https://via.placeholder.com/150',
    ),
    Property(
      id: 'offc3',
      category: PropertyCategory.office,
      location: LatLng(25.203, 55.264),
      price: 340000,
      imageUrl: 'https://via.placeholder.com/150',
    ),
    Property(
      id: 'offc4',
      category: PropertyCategory.office,
      location: LatLng(25.202, 55.263),
      price: 310000,
      imageUrl: 'https://via.placeholder.com/150',
    ),
    Property(
      id: 'offc5',
      category: PropertyCategory.office,
      location: LatLng(25.204, 55.262),
      price: 330000,
      imageUrl: 'https://via.placeholder.com/150',
    ),
  ];
}
