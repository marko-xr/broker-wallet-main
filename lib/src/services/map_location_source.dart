import 'dart:async';

import 'package:broker_wallet/src/common/data/owner_location_codec.dart';
import 'package:broker_wallet/src/common/data/uae_area_catalog.dart';
import 'package:broker_wallet/src/common/data/owner_property_types.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offices_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/watchmen_model.dart';
import 'package:broker_wallet/src/repositories/repository_provider.dart';
import 'package:broker_wallet/src/services/core_entity_mutation_notifier.dart';
import 'package:broker_wallet/src/services/map_location_data.dart';
import 'package:broker_wallet/src/services/map_places_loader.dart';
import 'package:broker_wallet/src/services/share/share_format.dart';
import 'package:broker_wallet/src/services/supabase_core_entities_service.dart';

/// How the app itself names the things the map filters by, so the map keeps no
/// vocabulary of its own: property types as the Offer forms and share messages
/// name them, an Owner's property type from the Owner suggestions, and the city
/// a saved location text names: first the way the Owner form writes it (the same
/// codec), then, for an Owner's, an Office's, a Watchman's text or an address
/// that is not written that way, any catalog city named in it as whole words in
/// either of the app's languages.
///
/// Built fresh for each read: the codec remembers the strings it first sees, and
/// the app's languages may not all have been loaded the first time.
MapVocabulary appMapVocabulary() {
  final codec = OwnerLocationCodec(lookup: AppLocalizations.translateFor);

  Iterable<String> namesOfKey(String key) => [
        for (final language in const <String>['en', 'ar'])
          AppLocalizations.translateFor(language, key),
      ].whereType<String>();

  return MapVocabulary(
    offerPropertyKey: (stored) =>
        MapPropertyTypes.canonicalKey(stored, ShareFormat.propertySubTypeKeys),
    ownerPropertyKey: (stored) =>
        OwnerPropertyTypes.match(stored, labelsOfKey: namesOfKey)?.key,
    cityOfText: (text) => codec.decode(text)?.city,
    cityLabels: (city) => namesOfKey(UaeAreaCatalog.cityKey(city)),
  );
}

/// The map's places, read from Supabase: the signed-in user's own Offers,
/// Owners, Offices and Watchmen, through the same four list reads Search and
/// every list screen use.
///
/// Every read is scoped to the signed-in user (by `owner_id` and RLS), so the
/// map can never see another user's records. Nothing is created until [load] is
/// first called.
class DefaultMapLocationSource implements MapLocationSource {
  DefaultMapLocationSource();

  SupabaseCoreEntitiesService? _supabase;

  @override
  String? get currentUserId =>
      RepositoryProvider.instance.authRepository.currentUserId;

  @override
  Stream<void> get changes => CoreEntityMutationNotifier.changes;

  @override
  Future<List<CachedLocationData>> load() async {
    final service = _supabase ??= SupabaseCoreEntitiesService();
    final results = await Future.wait<List<dynamic>>([
      service.getOffers().first,
      service.getOwners().first,
      service.getOffices().first,
      service.getWatchmen().first,
    ]);
    return MapLocationMapper.all(
      offers: results[0].cast<OfferModel>(),
      owners: results[1].cast<OwnerModel>(),
      offices: results[2].cast<OfficeModel>(),
      watchmen: results[3].cast<WatchmenModel>(),
      vocabulary: appMapVocabulary(),
    );
  }
}
