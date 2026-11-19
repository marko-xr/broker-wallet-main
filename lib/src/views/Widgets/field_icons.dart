import 'package:flutter/material.dart';

/// The one icon for each kind of record field, used by the list cards, the
/// search and Favorites cards and the details screens alike, so a field
/// looks the same wherever it appears and no two fields share an icon.
///
/// All are Material outlined icons, one style throughout.
abstract final class FieldIcons {
  // People and contact.
  static const IconData name = Icons.person_outline;
  static const IconData manager = Icons.badge_outlined;
  static const IconData phone = Icons.phone_outlined;
  static const IconData notes = Icons.sticky_note_2_outlined;

  // Places.
  static const IconData office = Icons.business_outlined;
  static const IconData building = Icons.apartment_outlined;
  static const IconData city = Icons.location_city_outlined;

  /// The districts within the city: a signpost, so it never looks like the
  /// [location] pin.
  static const IconData areas = Icons.signpost_outlined;
  static const IconData location = Icons.location_on_outlined;
  static const IconData map = Icons.map_outlined;

  // The property.
  /// Villa, Apartment, Office…: the kind of unit (a house beside a building:
  /// residential or commercial).
  static const IconData specificType = Icons.home_work_outlined;
  static const IconData area = Icons.square_foot_outlined;
  static const IconData price = Icons.payments_outlined;
  static const IconData bedrooms = Icons.bed_outlined;
  static const IconData bathrooms = Icons.bathtub_outlined;

  // The deal.
  static const IconData rent = Icons.key_outlined;
  static const IconData sale = Icons.sell_outlined;
  static IconData dealType({required bool isRent}) => isRent ? rent : sale;

  /// Residential, Commercial, Furnished: the property's category.
  static IconData propertyCategory(String? category) {
    switch (category?.trim().toLowerCase()) {
      case 'residential':
        return Icons.home_outlined;
      case 'commercial':
        return Icons.storefront_outlined;
      case 'furnished':
        return Icons.chair_outlined;
      default:
        return Icons.domain_outlined;
    }
  }
}
