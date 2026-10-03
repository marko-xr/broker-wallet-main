import 'package:intl/intl.dart';

import 'package:broker_wallet/src/common/data/uae_area_catalog.dart';
import 'package:broker_wallet/src/services/phone_input_service.dart';
import 'package:broker_wallet/src/services/share/share_labels.dart';

/// How the pieces of a shared message are written: phone numbers, prices, city
/// and area names, property types, map links and file names.
///
/// Everything here reads the app's own sources of truth — the UAE area catalog,
/// the ARB files and the phone formatter the detail screens use — and keeps no
/// translation table of its own. Every function returns null (or an empty list)
/// for a value there is nothing useful to say about, so a message never carries
/// an empty label, a raw key or the word "null".
abstract final class ShareFormat {
  static const String _lri = '\u2066';
  static const String _pdi = '\u2069';

  static final NumberFormat _grouped = NumberFormat('#,##0.##', 'en');

  /// [value] trimmed, or null when it is empty or a placeholder that was stored
  /// as text (`null`, `undefined`, `n/a`).
  static String? clean(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    switch (trimmed.toLowerCase()) {
      case 'null':
      case 'undefined':
      case 'n/a':
        return null;
    }
    return trimmed;
  }

  /// Keeps a left-to-right token (a phone number, a link, an amount) in reading
  /// order inside an Arabic message, where its digit groups would otherwise
  /// appear reversed. English messages are left exactly as they are.
  static String ltr(String value, ShareLabels labels) =>
      labels.isRtl && value.isNotEmpty ? '$_lri$value$_pdi' : value;

  /// The phone number as the detail screens show it (`+971 50 123 4567`), or
  /// null when there is no number. The formatter's own invisible mark is
  /// dropped: the message wraps the number itself where it needs to.
  static String? phone(String? raw, ShareLabels labels) {
    final value = clean(raw);
    if (value == null || !RegExp(r'\d').hasMatch(value)) return null;
    final shown =
        PhoneInputService.formatForDisplay(value).replaceAll('\u200E', '');
    if (shown.isEmpty) return null;
    return ltr(shown, labels);
  }

  /// `AED 2,500,000` (English) or `2,500,000 درهم` (Arabic).
  static String withCurrency(
    String amount,
    String currency,
    ShareLabels labels,
  ) =>
      labels.isRtl ? '${ltr(amount, labels)} $currency' : '$currency $amount';

  /// The price of a record whose model stores a minimum and a maximum as typed
  /// text, in the app's currency (AED): `AED 1,000,000 - 1,500,000`, or just the
  /// one amount when only one is present or both are equal.
  static String? price({
    required String? min,
    required String? max,
    required ShareLabels labels,
  }) {
    final low = _amount(min);
    final high = _amount(max);
    if (low == null && high == null) return null;

    final parts = <_Amount>[
      if (low != null) low,
      if (high != null && (low == null || high.text != low.text)) high,
    ];
    final joined = parts.map((a) => a.text).join(' - ');
    if (!parts.every((a) => a.isNumeric)) return joined;
    return withCurrency(joined, labels.text('aed'), labels);
  }

  /// An amount of money held as a number, in [currencyCode] (AED when absent).
  static String? money(
    double? value,
    ShareLabels labels, {
    String? currencyCode,
  }) {
    if (value == null || value.isNaN || value.isInfinite) return null;
    final code = (clean(currencyCode) ?? 'AED').toUpperCase();
    final currency = code == 'AED' ? (labels.maybe('aed') ?? code) : code;
    return withCurrency(_grouped.format(value), currency, labels);
  }

  /// A number typed as text (`1800`, `2,500.5`) with thousands separators, or
  /// the text itself when it is not a number.
  static String? number(String? raw) => _amount(raw)?.text;

  static _Amount? _amount(String? raw) {
    final value = clean(raw);
    if (value == null) return null;
    final parsed = double.tryParse(value.replaceAll(RegExp(r'[,\s]'), ''));
    if (parsed == null || parsed.isNaN || parsed.isInfinite) {
      return _Amount(value, false);
    }
    return _Amount(_grouped.format(parsed), true);
  }

  // ---------- City, areas and property types ----------

  /// The city's name in the message's language. A stored name the catalog knows
  /// (in any case or spacing) is localized; an unknown one is shown as stored.
  static String? city(String? stored, ShareLabels labels) {
    final value = clean(stored);
    if (value == null) return null;

    final wanted = _normalizeName(value);
    String? key;
    for (final city in UaeAreaCatalog.supportedCities) {
      if (city == value || _normalizeName(city) == wanted) {
        key = UaeAreaCatalog.cityKey(city);
        break;
      }
    }
    if (key == null) {
      for (final city in UaeAreaCatalog.supportedCities) {
        final english = labels.english(UaeAreaCatalog.cityKey(city));
        if (english != null && _normalizeName(english) == wanted) {
          key = UaeAreaCatalog.cityKey(city);
          break;
        }
      }
    }
    return (key == null ? null : labels.maybe(key)) ?? _fallback(value, labels);
  }

  /// The areas' names in the message's language, in the order stored, each once.
  /// An area the catalog does not know is shown as stored, never as a raw key
  /// when a localized name exists for it.
  static List<String> areas(Iterable<String> stored, ShareLabels labels) {
    final seen = <String>{};
    final names = <String>[];
    for (final item in stored) {
      final name = area(item, labels);
      if (name != null && seen.add(name)) names.add(name);
    }
    return names;
  }

  static String? area(String? stored, ShareLabels labels) {
    final value = clean(stored);
    if (value == null) return null;

    final key = _areaKey(value, labels);
    if (key != null) {
      final label = labels.maybe(key);
      if (label != null) return label;
    }
    return _fallback(value, labels);
  }

  /// The catalog key [value] stands for: the key itself, the key in another
  /// case or spacing, or an English name an older picker stored.
  static String? _areaKey(String value, ShareLabels labels) {
    if (UaeAreaCatalog.isSupported(value)) return value;

    final wanted = _normalizeName(value);
    final keys = <String>[
      for (final city in UaeAreaCatalog.supportedCities) ...[
        ...UaeAreaCatalog.areasFor(city),
        ...(UaeAreaCatalog.legacyOnlyAreas[city] ?? const <String>[]),
      ],
    ];
    for (final key in keys) {
      if (_normalizeName(key) == wanted) return key;
    }
    for (final key in keys) {
      final english = labels.english(key);
      if (english == null) continue;
      final plain = english.replaceAll(RegExp(r'\s*\([^)]*\)'), '');
      if (_normalizeName(english) == wanted ||
          _normalizeName(plain) == wanted) {
        return key;
      }
    }
    return null;
  }

  /// What to show for a stored value the catalog does not know: its own
  /// localized name when the ARB files happen to have one, else the value itself
  /// with a camel-case key turned into words.
  static String _fallback(String value, ShareLabels labels) {
    if (!RegExp(r'\s').hasMatch(value)) {
      final known = labels.maybe(value);
      if (known != null) return known;
    }
    return humanize(value);
  }

  /// `oldAreaKey` becomes `Old Area Key`; anything that is not a single
  /// camel-case token (a name with spaces, Arabic text) is returned unchanged.
  static String humanize(String value) {
    if (value.isEmpty || !RegExp(r'^[A-Za-z0-9]+$').hasMatch(value)) {
      return value;
    }
    final spaced = value.replaceAllMapped(
      RegExp(r'(?<=[a-z0-9])(?=[A-Z])'),
      (_) => ' ',
    );
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  static String _normalizeName(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

  /// The property types the Request and Offer forms offer (and older ones
  /// stored), each of them also an ARB key.
  static const List<String> propertySubTypeKeys = <String>[
    'apartment',
    'villa',
    'studio',
    'townhouse',
    'penthouse',
    'compound',
    'duplex',
    'fullFloor',
    'halfFloor',
    'wholeBuilding',
    'land',
    'bulkRentUnit',
    'bungalow',
    'hotelAndHotelApartment',
    'officeSpace',
    'retail',
    'warehouse',
    'shop',
    'showRoom',
    'bulkSaleUnit',
    'factory',
    'laborCamp',
    'staffAccommodation',
    'businessCentre',
    'farm',
    'offices',
  ];

  /// The main property category (`residential`, `commercial`, `furnished`) in the
  /// message's language, or the stored text capitalized when it is not one.
  static String? mainPropertyType(String? stored, ShareLabels labels) {
    final value = clean(stored);
    if (value == null) return null;
    final label = labels.maybe(value.toLowerCase());
    if (label != null) return label;
    return value[0].toUpperCase() + value.substring(1);
  }

  /// The specific property type (`villa`, `officeSpace`, …) in the message's
  /// language, or the stored text when it is not one the forms know.
  static String? propertyType(String? stored, ShareLabels labels) {
    final value = clean(stored);
    if (value == null) return null;
    var wanted = value.toLowerCase().replaceAll(' ', '').replaceAll('&', 'and');
    if (wanted == 'hotelhotelapartment') wanted = 'hotelandhotelapartment';
    for (final key in propertySubTypeKeys) {
      if (key.toLowerCase() == wanted) return labels.maybe(key) ?? value;
    }
    return value;
  }

  /// Whether a property of this specific type is described by its rooms and
  /// bathrooms. The detail screens show them for these three only, so a share
  /// does not claim `Rooms: 1` for a plot of land.
  static bool showsRoomsAndBathrooms(String? specificType) {
    switch (clean(specificType)?.toLowerCase()) {
      case 'villa':
      case 'apartment':
      case 'studio':
        return true;
    }
    return false;
  }

  // ---------- Map ----------

  /// The same rule the detail screens apply before they offer the map: both
  /// coordinates present, in range, and not the (0, 0) of an unset pin.
  static bool validLatLng(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    if (lat.isNaN || lng.isNaN) return false;
    if (lat == 0.0 && lng == 0.0) return false;
    if (lat < -90 || lat > 90) return false;
    if (lng < -180 || lng > 180) return false;
    return true;
  }

  /// The public map link the detail screens open for the same coordinates.
  static String mapLink(double lat, double lng) =>
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng';

  // ---------- File names ----------

  /// [raw] reduced to letters and digits joined by single hyphens, at most
  /// [maxLength] characters, or empty when nothing is left. Whatever a person
  /// typed — slashes, dots, quotes, line breaks — cannot reach a path.
  static String fileStem(String? raw, {int maxLength = 40}) {
    final value = clean(raw) ?? '';
    var stem = value.replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '-');
    stem = stem.replaceAll(RegExp(r'^-+|-+$'), '');
    if (stem.runes.length > maxLength) {
      stem = String.fromCharCodes(stem.runes.take(maxLength))
          .replaceAll(RegExp(r'-+$'), '');
    }
    return stem;
  }
}

class _Amount {
  const _Amount(this.text, this.isNumeric);

  final String text;
  final bool isNumeric;
}
