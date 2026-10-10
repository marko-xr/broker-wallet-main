import 'package:broker_wallet/src/common/data/uae_city_matcher.dart';
import 'package:broker_wallet/src/common/data/uae_coordinate_sanity.dart';
import 'package:broker_wallet/src/constants/location_filter.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offices_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/watchmen_model.dart';
import 'package:broker_wallet/src/services/map_city_geography.dart';
import 'package:broker_wallet/src/services/map_price.dart';

/// Rent or sale, as an Offer stores it. Only an Offer has one.
enum MapTransaction {
  rent,
  sale;

  /// The canonical value an Offer stores: `rent` or `sell` (`sale` is the same
  /// word as the app's own label key). Anything else — free text, an empty
  /// value, a record that has no such field — is no transaction at all: it is
  /// never guessed from words.
  static MapTransaction? fromStored(String? stored) {
    switch (stored?.trim().toLowerCase()) {
      case 'rent':
        return MapTransaction.rent;
      case 'sell':
      case 'sale':
        return MapTransaction.sale;
    }
    return null;
  }
}

/// One place on the map, in plain values (no map types), as the map keeps it
/// between visits.
///
/// [title] and [address] are exactly what the record says, and empty when it
/// says nothing: the screen words the empty case in the app's language, so no
/// English placeholder is ever baked in here.
///
/// [city], [propertyType] and [transaction] are what the map's filters look at.
/// Each is the record's own canonical value, or null when the record has none
/// (an Office has no property type; only an Offer has a transaction). [price]
/// is the one number the price ordering ranks by: only an Offer has one, and a
/// price that cannot be read is null, never zero.
class CachedLocationData {
  const CachedLocationData({
    required this.id,
    required this.title,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.type,
    this.phoneNumber,
    this.mediaUrl,
    this.mediaUrls = const <String>[],
    this.additionalData = const <String, dynamic>{},
    this.city,
    this.propertyType,
    this.transaction,
    this.price,
    this.cityConflict = false,
  });

  final String id;
  final String title;
  final String address;
  final double latitude;
  final double longitude;
  final LocationFilter type;
  final String? phoneNumber;
  final String? mediaUrl;
  final List<String> mediaUrls;
  final Map<String, dynamic> additionalData;

  /// A city of the catalog the forms use, spelled as the catalog does.
  final String? city;

  /// A property-type key (also its localization key), such as `villa`.
  final String? propertyType;

  final MapTransaction? transaction;

  /// The amount (above zero) the price ordering ranks this place by; null when
  /// the place has no usable price. See [MapPrice.comparable].
  final double? price;

  /// The record's city and its pin disagree: [city] says one listed city, and
  /// the pin is clearly in the core of another (an Offer saved as Abu Dhabi with
  /// its pin in Ajman). Such a place is not shown as a place of [city] by the
  /// City filter, and never drags the camera to its pin when [city] is chosen; it
  /// still shows with every city. See [MapCityGeography].
  final bool cityConflict;

  /// Identifies the place among all the map's places: its kind and its id.
  String get key => '${type.name}:$id';
}

/// How the app writes things the map filters by. The map does not keep a
/// second vocabulary: it asks the app's own canonical sources, passed in here
/// so the mapper itself stays plain Dart.
class MapVocabulary {
  const MapVocabulary({
    this.offerPropertyKey,
    this.ownerPropertyKey,
    this.cityOfText,
    this.cityLabels,
  });

  /// No vocabulary: only what needs none (the city of an Offer) is resolved.
  static const MapVocabulary none = MapVocabulary();

  /// Whether this vocabulary lets the mapper read a city out of a saved
  /// location text (an Owner's, an Office's, a Watchman's, an address). Without
  /// it only a record's structured city is read.
  bool get readsLocationText => cityOfText != null || cityLabels != null;

  /// The property-type key of an Offer's stored specific type, or null.
  final String? Function(String stored)? offerPropertyKey;

  /// The property-type key of an Owner's stored property type, or null when it
  /// is the owner's own wording.
  final String? Function(String stored)? ownerPropertyKey;

  /// The city a saved location text starts with in the way the Owner form writes
  /// it (`Area, City`), as the catalog spells it, or null.
  final String? Function(String text)? cityOfText;

  /// The names the app writes a catalog city with, in each of its languages
  /// (given the catalog's own spelling of the city). They let a location text
  /// written in Arabic name its city as well as one written in English.
  final Iterable<String> Function(String city)? cityLabels;
}

/// Property types as the app's forms and share messages name them.
abstract final class MapPropertyTypes {
  /// The key in [knownKeys] that a stored specific type names, or null. The same
  /// reading as `ShareFormat.propertyType`: case, spaces and `&` do not matter,
  /// and the two spellings of "hotel and hotel apartment" are one type.
  static String? canonicalKey(String? stored, Iterable<String> knownKeys) {
    final value = stored?.trim();
    if (value == null || value.isEmpty) return null;
    var wanted = value.toLowerCase().replaceAll(' ', '').replaceAll('&', 'and');
    if (wanted == 'hotelhotelapartment') wanted = 'hotelandhotelapartment';
    for (final key in knownKeys) {
      if (key.toLowerCase() == wanted) return key;
    }
    return null;
  }
}

/// Turns the user's records into the places the map shows.
///
/// One rule for every backend: a record is a place when it has an id (the map
/// opens its details by id) and a position the map can show ([isMapLocation]).
abstract final class MapLocationMapper {
  /// The rule the detail screens apply before they offer the map: both
  /// coordinates present, in range, and not the (0, 0) of an unset pin.
  static bool isUsableCoordinate(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    if (lat.isNaN || lng.isNaN || lat.isInfinite || lng.isInfinite) {
      return false;
    }
    if (lat == 0.0 && lng == 0.0) return false;
    if (lat < -90 || lat > 90) return false;
    if (lng < -180 || lng > 180) return false;
    return true;
  }

  /// Whether a RECORD's pin is a position the map can show: a usable coordinate
  /// ([isUsableCoordinate]) that could be inside the UAE
  /// ([UaeCoordinateSanity], a coarse country-level check, not a border).
  ///
  /// A record that fails is simply not a place, the same as a record with no
  /// pin: no marker, no part in any camera, no match for any filter, Nearby
  /// included. It is not an error and it does not fail the read; the record is
  /// not changed or deleted and still shows in the app's lists and details.
  ///
  /// This judges what a record says, never where the DEVICE is: a phone abroad
  /// still has a position ("my location", Nearby), so those keep
  /// [isUsableCoordinate].
  static bool isMapLocation(double? lat, double? lng) =>
      isUsableCoordinate(lat, lng) &&
      UaeCoordinateSanity.couldBeInUae(lat!, lng!);

  // English names and localization keys only: a vocabulary adds the app's
  // labels in each language (see [_cityOf]).
  static final UaeCityMatcher _englishCities = UaeCityMatcher();

  /// The catalog's own spelling of the city [stored] names (case, spaces and
  /// hyphens do not matter), or null when it is not one of the catalog's cities.
  static String? canonicalCity(String? stored) =>
      _englishCities.canonical(stored);

  /// The catalog city a record is in.
  ///
  /// Its structured city comes first when it has a usable one (an Offer's
  /// selected city). Failing that, and only when [vocabulary] lets the map read
  /// text, the city its saved location text names: the way the Owner form
  /// writes it, then any city named in the text as whole words, in either of the
  /// app's languages (`Ajman, Al Jurf` and `Al Jurf, Ajman` are both Ajman).
  /// [texts] are tried in order and the first that names a city wins. Nothing is
  /// geocoded and nothing stored is changed.
  static String? _cityOf(
    UaeCityMatcher matcher,
    MapVocabulary vocabulary, {
    String? structured,
    required Iterable<String?> texts,
  }) {
    final chosen = matcher.canonical(structured);
    if (chosen != null) return chosen;
    if (!vocabulary.readsLocationText) return null;

    for (final raw in texts) {
      final text = raw?.trim();
      if (text == null || text.isEmpty) continue;
      final written = matcher.canonical(vocabulary.cityOfText?.call(text));
      if (written != null) return written;
      final named = matcher.cityIn(text);
      if (named != null) return named;
    }
    return null;
  }

  static UaeCityMatcher _matcherFor(MapVocabulary vocabulary) =>
      vocabulary.cityLabels == null
          ? _englishCities
          : UaeCityMatcher(labelsOf: vocabulary.cityLabels);

  static List<CachedLocationData> offers(
    Iterable<OfferModel> offers, {
    MapVocabulary vocabulary = MapVocabulary.none,
  }) {
    final matcher = _matcherFor(vocabulary);
    final out = <CachedLocationData>[];
    for (final offer in offers) {
      final id = _id(offer.id);
      final lat = offer.pickUpLatitude;
      final lng = offer.pickUpLongitude;
      if (id == null || !isMapLocation(lat, lng)) continue;
      final city = _cityOf(
        matcher,
        vocabulary,
        structured: offer.selectedCity,
        texts: [offer.location, offer.pickUpAddress, offer.pickUpLocation],
      );
      out.add(
        CachedLocationData(
          id: id,
          title: offer.specificPropertyType.trim(),
          address: _firstText([offer.pickUpAddress, offer.pickUpLocation]),
          latitude: lat!,
          longitude: lng!,
          type: LocationFilter.offers,
          phoneNumber: _textOrNull(offer.phoneNumber),
          mediaUrl: _textOrNull(offer.mediaUrl),
          mediaUrls: _texts(offer.mediaUrls),
          additionalData: {
            'offerType': offer.offerType,
            'city': offer.selectedCity,
            'minPrice': offer.minPrice,
            'maxPrice': offer.maxPrice,
            'propertyType': offer.specificPropertyType,
          },
          city: city,
          cityConflict: MapCityGeography.conflicts(city, lat, lng),
          propertyType: _propertyKey(
            vocabulary.offerPropertyKey,
            offer.specificPropertyType,
          ),
          transaction: MapTransaction.fromStored(offer.offerType),
          price: MapPrice.comparable(
            minPrice: offer.minPrice,
            maxPrice: offer.maxPrice,
          ),
        ),
      );
    }
    return out;
  }

  static List<CachedLocationData> owners(
    Iterable<OwnerModel> owners, {
    MapVocabulary vocabulary = MapVocabulary.none,
  }) {
    final matcher = _matcherFor(vocabulary);
    final out = <CachedLocationData>[];
    for (final owner in owners) {
      final id = _id(owner.id);
      final lat = owner.pickUpLatitude;
      final lng = owner.pickUpLongitude;
      if (id == null || !isMapLocation(lat, lng)) continue;
      final city = _cityOf(
        matcher,
        vocabulary,
        texts: [
          owner.propertyLocation,
          owner.pickUpAddress,
          owner.pickUpLocation,
        ],
      );
      out.add(
        CachedLocationData(
          id: id,
          title: owner.name.trim(),
          address: _firstText([owner.pickUpAddress, owner.pickUpLocation]),
          latitude: lat!,
          longitude: lng!,
          type: LocationFilter.owners,
          phoneNumber: _textOrNull(owner.phoneNumber),
          mediaUrl: _textOrNull(owner.mediaUrl),
          mediaUrls: _texts(owner.mediaUrls),
          additionalData: {
            'typeOfProperties': owner.typeOfProperties,
            'propertyLocation': owner.propertyLocation,
          },
          city: city,
          cityConflict: MapCityGeography.conflicts(city, lat, lng),
          propertyType: _propertyKey(
            vocabulary.ownerPropertyKey,
            owner.typeOfProperties,
          ),
        ),
      );
    }
    return out;
  }

  static List<CachedLocationData> offices(
    Iterable<OfficeModel> offices, {
    MapVocabulary vocabulary = MapVocabulary.none,
  }) {
    final matcher = _matcherFor(vocabulary);
    final out = <CachedLocationData>[];
    for (final office in offices) {
      final id = _id(office.id);
      final lat = office.pickUpLatitude;
      final lng = office.pickUpLongitude;
      if (id == null || !isMapLocation(lat, lng)) continue;
      final city = _cityOf(
        matcher,
        vocabulary,
        texts: [
          office.officeLocation,
          office.pickUpAddress,
          office.pickUpLocation,
        ],
      );
      out.add(
        CachedLocationData(
          id: id,
          title: office.officeName.trim(),
          address: _firstText([office.pickUpAddress, office.pickUpLocation]),
          latitude: lat!,
          longitude: lng!,
          type: LocationFilter.offices,
          phoneNumber: _textOrNull(office.phoneNumber),
          additionalData: {
            'managerName': office.managerName,
            'officeLocation': office.officeLocation,
          },
          city: city,
          cityConflict: MapCityGeography.conflicts(city, lat, lng),
        ),
      );
    }
    return out;
  }

  static List<CachedLocationData> watchmen(
    Iterable<WatchmenModel> watchmen, {
    MapVocabulary vocabulary = MapVocabulary.none,
  }) {
    final matcher = _matcherFor(vocabulary);
    final out = <CachedLocationData>[];
    for (final watchman in watchmen) {
      final id = _id(watchman.id);
      final lat = watchman.pickUpLatitude;
      final lng = watchman.pickUpLongitude;
      if (id == null || !isMapLocation(lat, lng)) continue;
      final city = _cityOf(
        matcher,
        vocabulary,
        texts: [
          watchman.buildingLocation,
          watchman.pickUpAddress,
          watchman.pickUpLocation,
        ],
      );
      out.add(
        CachedLocationData(
          id: id,
          title: watchman.name.trim(),
          address: _firstText([
            watchman.pickUpAddress,
            watchman.pickUpLocation,
            watchman.buildingLocation,
          ]),
          latitude: lat!,
          longitude: lng!,
          type: LocationFilter.watchmen,
          phoneNumber: _textOrNull(watchman.phoneNumber),
          additionalData: {
            'buildingName': watchman.buildingName,
            'buildingLocation': watchman.buildingLocation,
          },
          city: city,
          cityConflict: MapCityGeography.conflicts(city, lat, lng),
        ),
      );
    }
    return out;
  }

  /// Every kind together, in the order the map's category selector lists them.
  static List<CachedLocationData> all({
    Iterable<OfferModel> offers = const <OfferModel>[],
    Iterable<OwnerModel> owners = const <OwnerModel>[],
    Iterable<OfficeModel> offices = const <OfficeModel>[],
    Iterable<WatchmenModel> watchmen = const <WatchmenModel>[],
    MapVocabulary vocabulary = MapVocabulary.none,
  }) =>
      [
        ...MapLocationMapper.offers(offers, vocabulary: vocabulary),
        ...MapLocationMapper.owners(owners, vocabulary: vocabulary),
        ...MapLocationMapper.offices(offices, vocabulary: vocabulary),
        ...MapLocationMapper.watchmen(watchmen, vocabulary: vocabulary),
      ];

  /// The last two meaningful parts of a comma-separated address ("Area, City"),
  /// for the small line under a place's name. Country names, street words,
  /// numbers and very short parts are not meaningful; when nothing is, the last
  /// parts of the address as it is.
  static String areaAndCity(String fullAddress) {
    if (fullAddress.isEmpty) return '';

    final parts = fullAddress
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return fullAddress;

    final meaningful = parts.where(_isMeaningfulPart).toList();
    if (meaningful.length >= 2) {
      return meaningful.skip(meaningful.length - 2).join(', ');
    }
    if (meaningful.length == 1) return meaningful.first;
    if (parts.length >= 2) return parts.skip(parts.length - 2).join(', ');
    return parts.last;
  }

  // "St" and "Street" are street words only as words: a part that merely
  // contains those letters ("Dubai Investments Park", "Dubai Studio City") is
  // an area.
  static final RegExp _streetWord = RegExp(r'\b(st|street)\b');
  static final RegExp _startsWithDigits = RegExp(r'^\d+');

  static bool _isMeaningfulPart(String part) {
    final lower = part.toLowerCase();
    return !lower.contains('united arab emirates') &&
        !lower.contains('uae') &&
        !lower.contains('emirates') &&
        !_streetWord.hasMatch(lower) &&
        !_startsWithDigits.hasMatch(part) &&
        part.length > 2;
  }

  static String? _propertyKey(String? Function(String)? resolver, String raw) {
    final text = raw.trim();
    if (resolver == null || text.isEmpty) return null;
    return resolver(text);
  }

  static String? _id(String? raw) {
    final id = raw?.trim();
    return id == null || id.isEmpty ? null : id;
  }

  static String? _textOrNull(String? raw) {
    final text = raw?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  /// The first of [candidates] that says something. A stored empty string is
  /// not an answer: it must not hide a later candidate that has one.
  static String _firstText(Iterable<String?> candidates) {
    for (final candidate in candidates) {
      final text = candidate?.trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return '';
  }

  static List<String> _texts(Iterable<String> raw) => List<String>.unmodifiable(
        raw.map((e) => e.trim()).where((e) => e.isNotEmpty),
      );
}
