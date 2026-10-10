import 'package:broker_wallet/src/common/data/owner_property_types.dart';
import 'package:broker_wallet/src/common/data/offer_property_types.dart';
import 'package:broker_wallet/src/constants/location_filter.dart';

/// The form vocabularies for the two map layers that have Property Type.
abstract final class MapPropertyTypeOptions {
  static List<String> forLayer(LocationFilter layer) => switch (layer) {
        LocationFilter.offers => OfferPropertyTypes.keys,
        LocationFilter.owners => [
            for (final option in OwnerPropertyTypes.options) option.key,
          ],
        _ => const <String>[],
      };

  static bool supports(LocationFilter layer, String key) =>
      forLayer(layer).contains(key);
}
