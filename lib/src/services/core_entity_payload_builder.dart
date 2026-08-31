import '../common/utils/phone_number_normalizer.dart';
import '../data/models/ScreensModel/brokers_model.dart';
import '../data/models/ScreensModel/offers_model.dart';
import '../data/models/ScreensModel/offices_model.dart';
import '../data/models/ScreensModel/owners_model.dart';
import '../data/models/ScreensModel/request_model.dart';
import '../data/models/ScreensModel/watchmen_model.dart';
import '../data/models/property_status.dart';

class CoreEntityPayloadBuilder {
  const CoreEntityPayloadBuilder._();

  static num? optionalNumber(String value, String field) {
    final normalized = value.replaceAll(',', '').trim();
    if (normalized.isEmpty) return null;
    final parsed = num.tryParse(normalized);
    if (parsed == null || !parsed.isFinite || parsed < 0) {
      throw CoreEntityValidationException('Please enter a valid $field.');
    }
    return parsed;
  }

  static String? phone(String number, String code) =>
      PhoneNumberNormalizer.normalizeOptional(
        phoneNumber: number,
        countryCode: code,
      );

  static (double?, double?) coordinates(double? latitude, double? longitude) {
    if ((latitude == null) != (longitude == null)) {
      throw const CoreEntityValidationException(
        'Please select a complete property location.',
      );
    }
    if (latitude != null && (latitude < -90 || latitude > 90)) {
      throw const CoreEntityValidationException('Invalid latitude.');
    }
    if (longitude != null && (longitude < -180 || longitude > 180)) {
      throw const CoreEntityValidationException('Invalid longitude.');
    }
    return (latitude, longitude);
  }

  static List<String> areas(List<String> values) => values
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList(growable: false);

  static Map<String, dynamic> forUpdate(Map<String, dynamic> insertPayload) {
    final payload = Map<String, dynamic>.from(insertPayload);
    payload.remove('id');
    payload.remove('owner_id');
    return payload;
  }

  static Map<String, dynamic> request(
    RequestModel model, {
    required String id,
    required String ownerId,
  }) {
    final min = optionalNumber(model.minPrice, 'minimum price');
    final max = optionalNumber(model.maxPrice, 'maximum price');
    _validatePriceRange(min, max);
    _validateTransactionType(model.requestType);
    _validateRequestStatus(model.status);
    return {
      'id': id,
      'owner_id': ownerId,
      'request_type': model.requestType,
      'selected_city': model.selectedCity.trim(),
      'location_text': model.location.trim(),
      'phone_number': model.phoneNumber.trim(),
      'country_code': model.countryCode.trim(),
      'phone_e164': phone(model.phoneNumber, model.countryCode),
      'min_price': min,
      'max_price': max,
      'square_footage': optionalNumber(model.squareFootage, 'square footage'),
      'notes': model.notes.trim(),
      'property_type': _optionalText(model.propertyType),
      'specific_property_type': model.specificPropertyType.trim(),
      'rooms': _nonnegative(model.rooms, 'rooms'),
      'bathrooms': _nonnegative(model.bathrooms, 'bathrooms'),
      'status': model.status.toFirestoreString(),
    };
  }

  static Map<String, dynamic> offer(
    OfferModel model, {
    required String id,
    required String ownerId,
  }) {
    final min = optionalNumber(model.minPrice, 'minimum price');
    final max = optionalNumber(model.maxPrice, 'maximum price');
    _validatePriceRange(min, max);
    _validateTransactionType(model.offerType);
    _validateOfferStatus(model.status);
    final pair = coordinates(model.pickUpLatitude, model.pickUpLongitude);
    return {
      'id': id,
      'owner_id': ownerId,
      'offer_type': model.offerType,
      'selected_city': model.selectedCity.trim(),
      'location_text': model.location.trim(),
      'phone_number': model.phoneNumber.trim(),
      'country_code': model.countryCode.trim(),
      'phone_e164': phone(model.phoneNumber, model.countryCode),
      'min_price': min,
      'max_price': max,
      'square_footage': optionalNumber(model.squareFootage, 'square footage'),
      'notes': model.notes.trim(),
      'property_type': _optionalText(model.propertyType),
      'specific_property_type': model.specificPropertyType.trim(),
      'rooms': _nonnegative(model.rooms, 'rooms'),
      'bathrooms': _nonnegative(model.bathrooms, 'bathrooms'),
      'pickup_location_text': model.pickUpLocation.trim(),
      'pickup_latitude': pair.$1,
      'pickup_longitude': pair.$2,
      'pickup_address': model.pickUpAddress.trim(),
      'legacy_uploaded_file_name': _optionalText(model.uploadedFileName),
      'status': model.status.toFirestoreString(),
    };
  }

  static Map<String, dynamic> owner(
    OwnerModel model, {
    required String id,
    required String ownerId,
  }) {
    final pair = coordinates(model.pickUpLatitude, model.pickUpLongitude);
    return {
      'id': id,
      'owner_id': ownerId,
      'name': _requiredName(model.name, 'owner'),
      'phone_number': model.phoneNumber.trim(),
      'country_code': model.countryCode.trim(),
      'phone_e164': phone(model.phoneNumber, model.countryCode),
      'property_type_text': model.typeOfProperties.trim(),
      'property_location': model.propertyLocation.trim(),
      'notes': model.notes.trim(),
      'pickup_location_text': model.pickUpLocation.trim(),
      'pickup_latitude': pair.$1,
      'pickup_longitude': pair.$2,
      'pickup_address': model.pickUpAddress.trim(),
      'legacy_uploaded_file_name': _optionalText(model.uploadedFileName),
    };
  }

  static Map<String, dynamic> office(
    OfficeModel model, {
    required String id,
    required String ownerId,
  }) {
    final pair = coordinates(model.pickUpLatitude, model.pickUpLongitude);
    return {
      'id': id,
      'owner_id': ownerId,
      'office_name': _requiredName(model.officeName, 'office'),
      'manager_name': model.managerName.trim(),
      'country_code': model.countryCode.trim(),
      'phone_number': model.phoneNumber.trim(),
      'phone_e164': phone(model.phoneNumber, model.countryCode),
      'office_location': model.officeLocation.trim(),
      'notes': model.notes.trim(),
      'pickup_location_text': model.pickUpLocation.trim(),
      'pickup_latitude': pair.$1,
      'pickup_longitude': pair.$2,
      'pickup_address': model.pickUpAddress.trim(),
    };
  }

  static Map<String, dynamic> broker(
    BrokerModel model, {
    required String id,
    required String ownerId,
  }) =>
      {
        'id': id,
        'owner_id': ownerId,
        'name': _requiredName(model.name, 'broker'),
        'country_code': model.countryCode.trim(),
        'phone_number': model.phoneNumber.trim(),
        'phone_e164': phone(model.phoneNumber, model.countryCode),
        'notes': model.notes.trim(),
      };

  static Map<String, dynamic> watchman(
    WatchmenModel model, {
    required String id,
    required String ownerId,
  }) {
    final pair = coordinates(model.pickUpLatitude, model.pickUpLongitude);
    return {
      'id': id,
      'owner_id': ownerId,
      'name': _requiredName(model.name, 'watchman'),
      'country_code': model.countryCode.trim(),
      'phone_number': model.phoneNumber.trim(),
      'phone_e164': phone(model.phoneNumber, model.countryCode),
      'building_name': model.buildingName.trim(),
      'notes': model.notes.trim(),
      'building_location': model.buildingLocation.trim(),
      'pickup_location_text': model.pickUpLocation.trim(),
      'pickup_latitude': pair.$1,
      'pickup_longitude': pair.$2,
      'pickup_address': model.pickUpAddress.trim(),
    };
  }

  static void _validateTransactionType(String value) {
    if (value != 'rent' && value != 'sell') {
      throw const CoreEntityValidationException(
        'Please select rent or sell.',
      );
    }
  }

  static void _validateOfferStatus(PropertyStatus status) {
    if (!PropertyStatus.offerStatuses.contains(status)) {
      throw const CoreEntityValidationException('Invalid offer status.');
    }
  }

  static void _validateRequestStatus(PropertyStatus status) {
    if (!PropertyStatus.requestStatuses.contains(status)) {
      throw const CoreEntityValidationException('Invalid request status.');
    }
  }

  static void _validatePriceRange(num? min, num? max) {
    if (min != null && max != null && min > max) {
      throw const CoreEntityValidationException(
        'Minimum price cannot exceed maximum price.',
      );
    }
  }

  static int _nonnegative(int value, String field) {
    if (value < 0) {
      throw CoreEntityValidationException('$field cannot be negative.');
    }
    return value;
  }

  static String _requiredName(String value, String entity) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw CoreEntityValidationException('Please enter the $entity name.');
    }
    return normalized;
  }

  static String? _optionalText(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}

class CoreEntityValidationException implements FormatException {
  const CoreEntityValidationException(this.message);

  @override
  final String message;
  @override
  int? get offset => null;
  @override
  dynamic get source => null;
  @override
  String toString() => message;
}
