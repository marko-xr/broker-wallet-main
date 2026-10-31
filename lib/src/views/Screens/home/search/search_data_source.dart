import 'package:broker_wallet/src/data/models/ScreensModel/brokers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offices_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/watchmen_model.dart';
import 'package:broker_wallet/src/repositories/repository_provider.dart';
import 'package:broker_wallet/src/services/supabase_core_entities_service.dart';

import 'search_engine.dart';

/// Where Search gets the records it looks through.
///
/// Search is local: it loads the signed-in user's own records once and searches
/// that copy. A data source is only that loading step, so the search itself can
/// be tested without a backend.
abstract class SearchDataSource {
  /// The signed-in user's id, or null when nobody is signed in. A copy of the
  /// records made for one user is never used for another.
  String? get currentUserId;

  /// Loads the signed-in user's records. Throws when they cannot be read — the
  /// caller decides what the user is told.
  Future<SearchData> load();
}

/// The app's own data, read from Supabase.
///
/// Every read is scoped to the signed-in user (by `owner_id` and RLS), so
/// Search can never see another user's records. Nothing is created until [load] is first called.
class DefaultSearchDataSource implements SearchDataSource {
  DefaultSearchDataSource();

  SupabaseCoreEntitiesService? _supabase;

  @override
  String? get currentUserId =>
      RepositoryProvider.instance.authRepository.currentUserId;

  @override
  Future<SearchData> load() {
    return _loadSupabase();
  }

  Future<SearchData> _loadSupabase() async {
    final service = _supabase ??= SupabaseCoreEntitiesService();
    final results = await Future.wait<List<dynamic>>([
      service.getRequests().first,
      service.getOffers().first,
      service.getOwners().first,
      service.getOffices().first,
      service.getBrokers().first,
      service.getWatchmen().first,
    ]);
    return SearchData(
      requests: results[0].cast<RequestModel>(),
      offers: results[1].cast<OfferModel>(),
      owners: results[2].cast<OwnerModel>(),
      offices: results[3].cast<OfficeModel>(),
      brokers: results[4].cast<BrokerModel>(),
      watchmen: results[5].cast<WatchmenModel>(),
    );
  }
}
