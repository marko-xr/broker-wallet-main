/// The one number the map ranks an Offer's price by.
///
/// Only an Offer has a price: it stores a minimum and a maximum as text. The
/// map never invents a price for an Owner, an Office or a Watchman, and never
/// reads a price out of a display string such as `AED 1.5M`: a price is either
/// plain digits (the forms write them, with `,` between thousands at most) or
/// it is no price.
abstract final class MapPrice {
  // `1500000`, `1500000.50`
  static final RegExp _plain = RegExp(r'^\d+(\.\d+)?$');

  // `1,500,000`, `1,500,000.50`: the groups must be real thousands.
  static final RegExp _grouped = RegExp(r'^\d{1,3}(,\d{3})+(\.\d+)?$');

  /// [stored] as an amount above zero, or null when it is not one: empty,
  /// letters, a currency, a malformed `1,5`, zero, a negative, or not finite. A
  /// price that cannot be read is never taken for zero.
  static double? parse(String? stored) {
    final text = stored?.trim();
    if (text == null || text.isEmpty) return null;
    if (!_plain.hasMatch(text) && !_grouped.hasMatch(text)) return null;
    final value = double.tryParse(text.replaceAll(',', ''));
    if (value == null || !value.isFinite || value <= 0) return null;
    return value;
  }

  /// The price an Offer is ranked by: its minimum when that is a usable price,
  /// otherwise its maximum, otherwise none.
  static double? comparable({String? minPrice, String? maxPrice}) =>
      parse(minPrice) ?? parse(maxPrice);
}
