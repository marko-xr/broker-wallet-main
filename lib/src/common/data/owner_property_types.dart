/// One quick-pick suggestion for an Owner's property type.
///
/// The [key] is both the suggestion's stable id and its localization key, so
/// the names live in the ARB files, once, in English and Arabic.
class OwnerPropertyType {
  const OwnerPropertyType(
    this.key, {
    this.aliasKeys = const <String>[],
    this.aliases = const <String>[],
  });

  final String key;

  /// Other localization keys whose text means the same thing (an existing
  /// `shop` or `retail` entry for `shopRetail`). Used only to recognise saved
  /// text; never shown.
  final List<String> aliasKeys;

  /// Other spellings that mean the same thing and are not in the ARB files
  /// (`Labour Camp`). Used only to recognise saved text; never shown.
  final List<String> aliases;
}

/// The property types an Owner can pick with one tap.
///
/// These are suggestions, not a restriction: an Owner's property type stays a
/// free-text field that accepts anything. A suggestion fills that field with
/// its own name; the field remains the only stored value, and a chip merely
/// shows as selected while the text still says what the suggestion says.
///
/// The names reuse the project's existing property-type vocabulary where it
/// already exists (`villa`, `apartment`, `showRoom`, `laborCamp`, …) rather
/// than inventing second spellings of the same idea.
abstract final class OwnerPropertyTypes {
  /// In priority order: residential, building and land, commercial,
  /// hospitality and other.
  static const List<OwnerPropertyType> options = [
    // Residential
    OwnerPropertyType('villa'),
    OwnerPropertyType('apartment'),
    OwnerPropertyType('townhouse'),
    OwnerPropertyType('studio'),
    OwnerPropertyType('penthouse', aliases: ['Pent House', 'بنتهاوس']),
    OwnerPropertyType('duplex'),
    // Building and land
    OwnerPropertyType('wholeBuilding'),
    OwnerPropertyType('residentialPlot'),
    OwnerPropertyType('commercialPlot'),
    OwnerPropertyType('land'),
    OwnerPropertyType('farm'),
    // Commercial
    OwnerPropertyType('office'),
    OwnerPropertyType(
      'shopRetail',
      aliasKeys: ['shop', 'retail'],
      aliases: ['Shop/Retail', 'محل/تجزئة'],
    ),
    OwnerPropertyType('warehouse'),
    OwnerPropertyType('showRoom', aliases: ['Showroom']),
    OwnerPropertyType('laborCamp', aliases: ['Labour Camp', 'سكن عمال']),
    // Hospitality and other
    OwnerPropertyType('hotel'),
    OwnerPropertyType('hotelApartment'),
    OwnerPropertyType('other'),
  ];

  /// The suggestion that [text] says, or null when it is the owner's own
  /// wording. [labelsOfKey] returns every name a localization key has (one per
  /// language the app supports), so text saved in Arabic still matches while
  /// the app is in English.
  ///
  /// The match ignores case and extra spaces and nothing else: a custom type
  /// that merely resembles a suggestion (`Villas`) is custom.
  static OwnerPropertyType? match(
    String text, {
    required Iterable<String> Function(String key) labelsOfKey,
  }) {
    final wanted = _normalize(text);
    if (wanted.isEmpty) return null;
    for (final option in options) {
      for (final key in <String>[option.key, ...option.aliasKeys]) {
        for (final label in labelsOfKey(key)) {
          if (_normalize(label) == wanted) return option;
        }
      }
      for (final alias in option.aliases) {
        if (_normalize(alias) == wanted) return option;
      }
    }
    return null;
  }

  static String _normalize(String text) => text
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'\s*/\s*'), '/')
      .toLowerCase();
}
