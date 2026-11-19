import '../common/data/offer_property_types.dart';
import '../common/data/uae_area_catalog.dart';
import '../common/data/uae_city_matcher.dart';
import '../common/localization/localization_delegate.dart';

abstract final class CompactPropertyLabels {
  static final _cities = UaeCityMatcher(
    labelsOf: (city) => _savedLabels(UaeAreaCatalog.cityKey(city)),
  );

  static String city(String stored, AppLocalizations loc) {
    final value = stored.trim();
    if (value.isEmpty) return loc.translate('noCitySelected');
    final city = _cities.canonical(value);
    return city == null ? value : loc.translate(UaeAreaCatalog.cityKey(city));
  }

  static String category(String? stored, AppLocalizations loc) => _property(
        stored,
        const ['residential', 'commercial', 'furnished'],
        'propertyTypeNotSpecified',
        loc,
      );

  static String subtype(String stored, AppLocalizations loc) => _property(
        stored,
        OfferPropertyTypes.keys,
        'notSpecified',
        loc,
      );

  static String _property(String? stored, List<String> keys, String missingKey,
      AppLocalizations loc) {
    final value = stored?.trim() ?? '';
    if (value.isEmpty) return loc.translate(missingKey);

    final normalized = _normalize(value);
    final wanted = normalized == 'hotelhotelapartment'
        ? 'hotelandhotelapartment'
        : normalized;
    for (final key in keys) {
      if (_normalize(key) == wanted ||
          _savedLabels(key).any((label) => _normalize(label) == wanted)) {
        return loc.translate(key);
      }
    }
    return value;
  }

  static final _separators = RegExp(r'[\s_-]+');

  static String _normalize(String value) =>
      value.toLowerCase().replaceAll('&', 'and').replaceAll(_separators, '');

  static Iterable<String> _savedLabels(String key) sync* {
    for (final language in ['en', 'ar']) {
      final label = AppLocalizations.translateFor(language, key);
      if (label != null) yield label;
    }
  }
}
