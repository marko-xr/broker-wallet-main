import 'package:broker_wallet/src/config/supabase_config.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/brokers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offices_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/watchmen_model.dart';
import 'package:broker_wallet/src/repositories/repository_provider.dart';
import 'package:broker_wallet/src/services/supabase_core_entities_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

/// The app's own data: Supabase when it is the auth authority, otherwise the
/// legacy Firestore collections of the signed-in user.
///
/// Every read is scoped to the signed-in user (Supabase by `owner_id` and RLS,
/// Firestore by the user's own document), so Search can never see another
/// user's records. Nothing is created until [load] is first called.
class DefaultSearchDataSource implements SearchDataSource {
  DefaultSearchDataSource();

  SupabaseCoreEntitiesService? _supabase;

  @override
  String? get currentUserId =>
      RepositoryProvider.instance.authRepository.currentUserId;

  @override
  Future<SearchData> load() {
    return SupabaseConfig.useSupabaseAuth ? _loadSupabase() : _loadFirestore();
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

  Future<SearchData> _loadFirestore() async {
    final userId = currentUserId;
    if (userId == null || userId.isEmpty) {
      throw StateError('A session is required.');
    }
    final firestore = FirebaseFirestore.instance;
    Future<QuerySnapshot<Map<String, dynamic>>> collection(String name) =>
        firestore.collection('users').doc(userId).collection(name).get();

    final snapshots = await Future.wait([
      collection('requests'),
      collection('offers'),
      collection('owners'),
      collection('offices'),
      collection('brokers'),
      collection('watchmen'),
    ]);

    return SearchData(
      requests: snapshots[0].docs.map(RequestModel.fromFirestore).toList(),
      offers: snapshots[1].docs.map(OfferModel.fromFirestore).toList(),
      owners: snapshots[2].docs.map(OwnerModel.fromFirestore).toList(),
      offices: snapshots[3].docs.map(OfficeModel.fromFirestore).toList(),
      brokers: snapshots[4].docs.map(BrokerModel.fromFirestore).toList(),
      watchmen: snapshots[5].docs.map(WatchmenModel.fromFirestore).toList(),
    );
  }
}
